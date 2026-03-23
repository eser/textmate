// TextFellow-Bridging-Header.h
// Exposes ObjC/C APIs to Swift code in the TextFellow app target.
//
// IMPORTANT: Only include pure C/ObjC headers here. Headers that
// include C++ code (oak/*, text/*, etc.) will cause compilation
// errors because bridging headers are compiled as ObjC, not ObjC++.

#import <Cocoa/Cocoa.h>

// tree-sitter C API
#include <tree_sitter/api.h>

// tree-sitter grammar entry points (C symbols — need extern "C" for ObjC++ mode)
#ifdef __cplusplus
extern "C" {
#endif
extern const TSLanguage *tree_sitter_json(void);
extern const TSLanguage *tree_sitter_c(void);
extern const TSLanguage *tree_sitter_javascript(void);
extern const TSLanguage *tree_sitter_python(void);
extern const TSLanguage *tree_sitter_go(void);
extern const TSLanguage *tree_sitter_rust(void);
extern const TSLanguage *tree_sitter_typescript(void);
extern const TSLanguage *tree_sitter_html(void);
extern const TSLanguage *tree_sitter_css(void);
extern const TSLanguage *tree_sitter_markdown(void);
extern const TSLanguage *tree_sitter_yaml(void);
#ifdef __cplusplus
}
#endif
