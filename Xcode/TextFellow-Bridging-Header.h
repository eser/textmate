// TextFellow-Bridging-Header.h
// Exposes ObjC/C APIs to Swift code in the TextFellow app target.
//
// IMPORTANT: Only include pure C/ObjC headers here. Headers that
// include C++ code (oak/*, text/*, etc.) will cause compilation
// errors because bridging headers are compiled as ObjC, not ObjC++.

#import <Cocoa/Cocoa.h>

// tree-sitter C API
#include <tree_sitter/api.h>
