#include "download.h"
#include "proxy.h"
#include "user_agent.h"
#include <cf/cf.h>
#include <text/format.h>
#include <text/case.h>
#include <oak/debug.h>
#import <Foundation/Foundation.h>

// ==============================
// = NSURLSession Delegate      =
// ==============================

struct NetworkDownloadContext
{
	std::vector<filter_t*> const* filters;
	bool const* stopFlag;
	double* progress;
	double progressMin;
	double progressMax;

	long statusCode;
	bool receivingBody;
	std::string error;
	bool filterFailed;
	int64_t expectedLength;
	int64_t receivedLength;
	dispatch_semaphore_t semaphore;
};

@interface NetworkDownloadDelegate : NSObject <NSURLSessionDataDelegate>
@property (nonatomic, assign) NetworkDownloadContext* context;
@end

@implementation NetworkDownloadDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                                 didReceiveResponse:(NSURLResponse *)response
                                  completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
	auto* ctx = self.context;
	NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
	ctx->statusCode = httpResponse.statusCode;
	ctx->expectedLength = httpResponse.expectedContentLength;

	if(ctx->statusCode >= 200 && ctx->statusCode < 300)
		ctx->receivingBody = true;

	// Deliver status line to filters
	std::string statusLine = text::format("HTTP/1.1 %ld", ctx->statusCode);
	for(auto const& filter : *ctx->filters)
	{
		if(!filter->receive_status(statusLine))
		{
			ctx->error = text::format("%s: receiving status", filter->name().c_str());
			ctx->filterFailed = true;
			completionHandler(NSURLSessionResponseCancel);
			return;
		}
	}

	// Deliver headers to filters individually
	NSDictionary* headers = httpResponse.allHeaderFields;
	for(NSString* key in headers)
	{
		std::string headerKey = text::lowercase(std::string([key UTF8String]));
		std::string headerValue = std::string([[headers objectForKey:key] UTF8String]);

		for(auto const& filter : *ctx->filters)
		{
			if(!filter->receive_header(headerKey, headerValue))
			{
				ctx->error = text::format("%s: receiving header", filter->name().c_str());
				ctx->filterFailed = true;
				completionHandler(NSURLSessionResponseCancel);
				return;
			}
		}
	}

	completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
                                     didReceiveData:(NSData *)data
{
	auto* ctx = self.context;

	// Check stop flag
	if(ctx->stopFlag && *ctx->stopFlag)
	{
		[dataTask cancel];
		return;
	}

	// Deliver data to filters
	for(auto const& filter : *ctx->filters)
	{
		if(!filter->receive_data((char const*)data.bytes, data.length))
		{
			ctx->error = text::format("%s: receiving data", filter->name().c_str());
			ctx->filterFailed = true;
			[dataTask cancel];
			return;
		}
	}

	ctx->receivedLength += data.length;

	// Update progress
	if(ctx->progress && ctx->receivingBody)
	{
		double fraction = ctx->expectedLength > 0 ? (double)ctx->receivedLength / ctx->expectedLength : 0;
		*ctx->progress = ctx->progressMin + (ctx->progressMax - ctx->progressMin) * fraction;
	}
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
                           didCompleteWithError:(NSError *)nsError
{
	auto* ctx = self.context;
	if(nsError && !ctx->filterFailed)
	{
		if(nsError.code != NSURLErrorCancelled)
			ctx->error = std::string([[nsError localizedDescription] UTF8String]);
	}
	dispatch_semaphore_signal(ctx->semaphore);
}

@end

// ============================================
// = network::request_t and download()        =
// ============================================

namespace network
{
	// =============
	// = request_t =
	// =============

	request_t::request_t (std::string const& url, filter_t* firstFilter, ...) : _url(url)
	{
		va_list ap;
		va_start(ap, firstFilter);
		for(; firstFilter; firstFilter = va_arg(ap, filter_t*))
			_filters.push_back(firstFilter);
		va_end(ap);
	}

	request_t& request_t::add_filter (filter_t* filter)                              { _filters.push_back(filter); return *this; }
	request_t& request_t::set_user_agent (std::string const& user_agent)             { _user_agent = user_agent; return *this; }
	request_t& request_t::set_entity_tag (std::string const& entity_tag)             { _entity_tag = entity_tag; return *this; }
	request_t& request_t::watch_stop_flag (bool const* stopFlag)                     { _stop_flag = stopFlag; return *this; }

	request_t& request_t::update_progress_variable (double* percentDone, double min, double max)
	{
		_progress     = percentDone;
		_progress_min = min;
		_progress_max = max;
		return *this;
	}

	// ============
	// = Download =
	// ============

	long download (request_t const& request, std::string* error)
	{
		for(auto const& filter : request._filters)
		{
			if(!filter->setup())
			{
				if(error)
					*error = text::format("%s: setup", filter->name().c_str());
				return 0;
			}
		}

		__block long resultCode = 0;

		@autoreleasepool
		{
			NSURL* nsURL = [NSURL URLWithString:[NSString stringWithUTF8String:request._url.c_str()]];
			if(!nsURL)
			{
				if(error)
					*error = "Invalid URL";
				return 0;
			}

			NSMutableURLRequest* urlRequest = [NSMutableURLRequest requestWithURL:nsURL];
			[urlRequest setHTTPShouldHandleCookies:NO];

			std::string const userAgent = request._user_agent == NULL_STR ? create_agent_info_string() : request._user_agent;
			[urlRequest setValue:[NSString stringWithUTF8String:userAgent.c_str()] forHTTPHeaderField:@"User-Agent"];

			if(request._entity_tag != NULL_STR)
				[urlRequest setValue:[NSString stringWithUTF8String:request._entity_tag.c_str()] forHTTPHeaderField:@"If-None-Match"];

			// NSURLSession handles Accept-Encoding and system proxies automatically

			dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

			// Copy private members into context (download() is a friend, so we have access)
			NetworkDownloadContext ctx;
			ctx.filters        = &request._filters;
			ctx.stopFlag       = request._stop_flag;
			ctx.progress       = request._progress;
			ctx.progressMin    = request._progress_min;
			ctx.progressMax    = request._progress_max;
			ctx.statusCode     = 0;
			ctx.receivingBody  = false;
			ctx.error          = NULL_STR;
			ctx.filterFailed   = false;
			ctx.expectedLength = 0;
			ctx.receivedLength = 0;
			ctx.semaphore      = semaphore;

			NetworkDownloadDelegate* delegate = [[NetworkDownloadDelegate alloc] init];
			delegate.context = &ctx;

			NSOperationQueue* delegateQueue = [[NSOperationQueue alloc] init];
			delegateQueue.maxConcurrentOperationCount = 1;

			NSURLSessionConfiguration* config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
			NSURLSession* session = [NSURLSession sessionWithConfiguration:config delegate:delegate delegateQueue:delegateQueue];

			NSURLSessionDataTask* task = [session dataTaskWithRequest:urlRequest];
			[task resume];

			// Poll for completion, checking stop flag periodically
			while(dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC)) != 0)
			{
				if(request._stop_flag && *request._stop_flag)
				{
					[task cancel];
					dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
					break;
				}
			}

			[session invalidateAndCancel];
			resultCode = ctx.statusCode;

			if(ctx.filterFailed || (ctx.error != NULL_STR && ctx.statusCode == 0))
			{
				if(error)
					*error = ctx.error;
				return 0;
			}

			if(ctx.error != NULL_STR && ctx.statusCode != 0)
			{
				if(error)
					*error = ctx.error;
			}

			if(resultCode == 304) // not modified so ignore filter errors
			{
				std::string endError;
				for(auto const& filter : request._filters)
					filter->receive_end(endError);
			}
			else if(resultCode != 0)
			{
				std::string endError = NULL_STR;
				for(auto const& filter : request._filters)
				{
					if(!filter->receive_end(endError))
					{
						if(error)
							*error = endError;
						return 0;
					}
				}
			}
		}

		return resultCode;
	}

} /* network */
