// TreeSitterColorBridge.mm — Bridges tree-sitter syntax to ObjC++
#if __has_include("TextFellow-Swift.h")

#import <MetalKit/MetalKit.h>
#import "TextFellow-Swift.h"

@interface TreeSitterColorBridge : NSObject
+ (BOOL)hasGrammarForExtension:(NSString*)ext;
@end

@implementation TreeSitterColorBridge

+ (BOOL)hasGrammarForExtension:(NSString*)ext
{
	if(!ext) return NO;
	return [[SW3TGrammarRegistry shared] hasGrammarForExtension:ext];
}

@end

#endif
