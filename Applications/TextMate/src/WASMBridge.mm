// WASMBridge.mm — Bridges WAMR runtime to TextMate
#if __has_include("TextFellow-Swift.h")

#import <MetalKit/MetalKit.h>
#import "TextFellow-Swift.h"

#if __has_include("wasm_export.h")
#define WAMR_AVAILABLE 1
#include "wasm_export.h"
#endif

@interface WASMBridge : NSObject
+ (BOOL)isAvailable;
@end

@implementation WASMBridge

+ (BOOL)isAvailable
{
#if WAMR_AVAILABLE
	static BOOL initialized = NO;
	static BOOL result = NO;

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		RuntimeInitArgs initArgs;
		memset(&initArgs, 0, sizeof(initArgs));
		initArgs.mem_alloc_type = Alloc_With_System_Allocator;

		result = wasm_runtime_full_init(&initArgs);
		initialized = YES;

		os_log_info(OS_LOG_DEFAULT, "WASMBridge: WAMR runtime init %{public}@",
			result ? @"succeeded" : @"failed");
	});

	return result;
#else
	return NO;
#endif
}

@end

#endif
