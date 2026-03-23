// LSPBridge.mm — Bridges LSP services (Swift) to TextMate (ObjC++)
#if __has_include("TextFellow-Swift.h")

#import <MetalKit/MetalKit.h>
#import "TextFellow-Swift.h"

NSNotificationName const SW3TLSPDidStartServer = @"SW3TLSPDidStartServer";

@interface LSPBridge : NSObject
+ (NSInteger)registeredServerCount;
+ (NSInteger)activeServerCount;
@end

@implementation LSPBridge

+ (NSInteger)registeredServerCount
{
	return [[SW3TLSPCoordinator shared] registeredServerCount];
}

+ (NSInteger)activeServerCount
{
	return [[SW3TLSPCoordinator shared] activeServerCount];
}

@end

#endif
