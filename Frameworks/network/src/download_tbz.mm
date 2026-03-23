#include "download_tbz.h"
#include "filter_check_signature.h"
#include "constants.h"
#include "user_agent.h"
#include "proxy.h"
#include "tbz.h"
#include <io/path.h>
#include <io/move_path.h>
#include <text/case.h>
#include <text/decode.h>
#include <text/format.h>
#import <Foundation/Foundation.h>

namespace network
{
	static std::string const kHTTPEntityTagAttribute = "org.w3.http.etag";

	namespace
	{
		struct tbz_download_context_t
		{
			tbz_download_context_t (key_chain_t const& keychain, double* progress, double start_progress, double stop_progress, bool const* stop_flag, int tbz_fd, int tmp_fd) : progress(progress), start_progress(start_progress), stop_progress(stop_progress), stop_flag(stop_flag), tbz_fd(tbz_fd), tmp_fd(tmp_fd), verify_signature(keychain, kHTTPSigneeHeader, kHTTPSignatureHeader)
			{
				verify_signature.setup();
			}

			void receive (size_t len)
			{
				received += len;
				if(progress)
					*progress = start_progress + (stop_progress - start_progress) * (total ? received / (double)total : 0);
			}

			bool should_stop () const
			{
				return stop_flag && *stop_flag;
			}

			bool modified = true;

			double* progress;
			double start_progress;
			double stop_progress;

			bool const* stop_flag;

			std::string etag = NULL_STR;

			int tbz_fd;
			int tmp_fd;

			network::check_signature_t verify_signature;

			size_t received = 0;
			size_t total = 0;

			long statusCode = 0;
			std::string error;
			bool stopped = false;
			dispatch_semaphore_t semaphore;
		};
	}
}

// ======================================
// = NSURLSession Delegate for TBZ      =
// ======================================

@interface TBZDownloadDelegate : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, assign) network::tbz_download_context_t* context;
@end

@implementation TBZDownloadDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                                 didReceiveResponse:(NSURLResponse *)response
                                  completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
	auto* ctx = self.context;
	NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
	ctx->statusCode = httpResponse.statusCode;

	if(ctx->statusCode == 304)
	{
		ctx->modified = false;
		completionHandler(NSURLSessionResponseAllow);
		return;
	}

	// Extract headers
	NSDictionary* headers = httpResponse.allHeaderFields;
	for(NSString* key in headers)
	{
		std::string header = text::lowercase(std::string([key UTF8String]));
		std::string value = std::string([[headers objectForKey:key] UTF8String]);

		if(header == "etag")
			ctx->etag = value;
		else if(header == "content-length")
			ctx->total = strtol(value.c_str(), nullptr, 10);
		else if(header == kHTTPSigneeHeader || header == kHTTPSignatureHeader)
			ctx->verify_signature.receive_header(header, value);
	}

	completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                                     didReceiveData:(NSData *)data
{
	auto* ctx = self.context;

	if(ctx->should_stop())
	{
		ctx->stopped = true;
		[dataTask cancel];
		return;
	}

	write(ctx->tbz_fd, data.bytes, data.length);
	write(ctx->tmp_fd, data.bytes, data.length);
	ctx->verify_signature.receive_data((char const*)data.bytes, data.length);
	ctx->receive(data.length);

	if(ctx->should_stop())
	{
		ctx->stopped = true;
		[dataTask cancel];
	}
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
                           didCompleteWithError:(NSError *)nsError
{
	auto* ctx = self.context;
	if(nsError && nsError.code != NSURLErrorCancelled)
		ctx->error = std::string([[nsError localizedDescription] UTF8String]);
	dispatch_semaphore_signal(ctx->semaphore);
}

@end

// ============================================
// = download_tbz() implementation            =
// ============================================

namespace network
{
	std::string download_tbz (std::string const& url, key_chain_t const& keyChain, std::string const& destination, std::string& error, double* progress, double progressStart, double progressStop, bool const* stopFlag)
	{
		std::string res = NULL_STR;

		@autoreleasepool
		{
			std::string tbzDestination = path::cache("dl_archive_contents");
			mkdir(tbzDestination.c_str(), S_IRWXU|S_IRWXG|S_IRWXO);
			tbz_t tbz(tbzDestination);

			std::string tmpPath = path::temp("dl_bytes");
			int tmpInput = open(tmpPath.c_str(), O_CREAT|O_TRUNC|O_WRONLY|O_CLOEXEC, S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH);

			// ==============
			// = NSURLSession =
			// ==============

			tbz_download_context_t data(keyChain, progress, progressStart, progressStop, stopFlag, tbz.input_fd(), tmpInput);
			data.semaphore = dispatch_semaphore_create(0);

			NSURL* nsURL = [NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()]];
			if(!nsURL)
			{
				error = "Invalid URL";
				close(tmpInput);
				unlink(tmpPath.c_str());
				path::remove(tbzDestination);
				return NULL_STR;
			}

			NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL:nsURL];
			[urlRequest setHTTPShouldHandleCookies:NO];
			[urlRequest setValue:[NSString stringWithUTF8String:create_agent_info_string().c_str()] forHTTPHeaderField:@"User-Agent"];

			// NSURLSession handles Accept-Encoding and system proxies automatically

			std::string const etag = path::get_attr(destination, kHTTPEntityTagAttribute);
			if(etag != NULL_STR)
				[urlRequest setValue:[NSString stringWithUTF8String:etag.c_str()] forHTTPHeaderField:@"If-None-Match"];

			TBZDownloadDelegate* delegate = [[TBZDownloadDelegate alloc] init];
			delegate.context = &data;

			NSOperationQueue* delegateQueue = [[NSOperationQueue alloc] init];
			delegateQueue.maxConcurrentOperationCount = 1;

			NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
			NSURLSession* session = [NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:delegateQueue];

			NSURLSessionDataTask* task = [session dataTaskWithRequest:urlRequest];
			[task resume];

			// Poll for completion, checking stop flag periodically
			while(dispatch_semaphore_wait(data.semaphore, dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC)) != 0)
			{
				if(stopFlag && *stopFlag)
				{
					[task cancel];
					dispatch_semaphore_wait(data.semaphore, DISPATCH_TIME_FOREVER);
					break;
				}
			}

			[session invalidateAndCancel];

			long serverReply = data.statusCode;

			if(!data.error.empty() && serverReply == 0)
			{
				if(data.stopped || (stopFlag && *stopFlag))
					error = "Download stopped.";
				else
					error = data.error;
			}

			// =============
			// = Post Download =
			// =============

			close(tmpInput);

			bool goodSignature = false;
			if(serverReply == 200)
			{
				if(goodSignature = data.verify_signature.receive_end(error))
				{
					path::set_attr(tmpPath, kHTTPEntityTagAttribute, data.etag);
					path::set_attr(tmpPath, kHTTPSigneeHeader,       data.verify_signature.signee());
					path::set_attr(tmpPath, kHTTPSignatureHeader,    data.verify_signature.signature());
					path::rename_or_copy(tmpPath, destination);
				}
			}
			else if(serverReply == 304)
			{
				struct stat buf;
				int fd = open(destination.c_str(), O_RDONLY|O_CLOEXEC);
				if(fd != -1 && fstat(fd, &buf) != -1)
				{
					char bytes[4096];
					data.total = buf.st_size;
					while(data.received < data.total && !data.should_stop())
					{
						ssize_t len = read(fd, bytes, sizeof(bytes));
						if(len == -1)
							break;

						write(tbz.input_fd(), bytes, len);
						data.receive(len);
					}
					close(fd);
				}
			}
			else if(serverReply != 0)
			{
				error = text::format("Unexpected server reply (%ld).", serverReply);
			}

			if(!goodSignature) // If not, tmpPath has been moved to destination
				unlink(tmpPath.c_str());

			if(tbz.wait_for_tbz())
			{
				if(serverReply == 304 || goodSignature)
					res = tbzDestination;
			}
			else if(serverReply == 200 || serverReply == 304)
			{
				error = "Extracting archive.";
			}

			if(res == NULL_STR)
				path::remove(tbzDestination);
		}

		return res;
	}

} /* network */
