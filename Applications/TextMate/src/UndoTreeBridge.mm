// UndoTreeBridge.mm — Bridges UndoTree<TextStorageSnapshot> (Swift) to TextMate buffer (ObjC++)
//
// Wraps the Swift branching undo tree so existing ObjC++ code can record
// snapshots and navigate undo/redo without knowing the Swift internals.

#if __has_include("TextFellow-Swift.h")

#import <MetalKit/MetalKit.h>
#import "TextFellow-Swift.h"
#import <AppKit/AppKit.h>

@interface UndoTreeBridge : NSObject
{
	UndoTreeHandle* _tree;
}

- (instancetype)init;

/// Records the current text as a snapshot in the undo tree.
- (void)recordState:(NSString*)text;

/// Moves to the previous state and returns its text, or nil if at the root.
- (NSString*)undo;

/// Moves to the next state and returns its text, or nil if at the tip.
- (NSString*)redo;

/// Returns YES if undo is possible.
- (BOOL)canUndo;

/// Returns YES if redo is possible.
- (BOOL)canRedo;

/// Returns the total number of nodes in the undo tree.
- (NSInteger)nodeCount;

@end

@implementation UndoTreeBridge

- (instancetype)init
{
	if((self = [super init]))
	{
		_tree = [[UndoTreeHandle alloc] init];
		os_log_debug(OS_LOG_DEFAULT, "UndoTreeBridge: initialized");
	}
	return self;
}

- (void)recordState:(NSString*)text
{
	if(!text)
		return;

	[_tree recordStateWithText:text];
}

- (NSString*)undo
{
	if(![_tree canUndo])
		return nil;

	return [_tree undo];
}

- (NSString*)redo
{
	if(![_tree canRedo])
		return nil;

	return [_tree redo];
}

- (BOOL)canUndo
{
	return [_tree canUndo];
}

- (BOOL)canRedo
{
	return [_tree canRedo];
}

- (NSInteger)nodeCount
{
	return [_tree nodeCount];
}

@end

#endif
