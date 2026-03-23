import Testing
@testable import TextFellow

@Suite("EditorConfig")
struct EditorConfigTests {
    @Test("pattern * matches any file")
    func wildcardPattern() {
        #expect(EditorConfig.matches(pattern: "*", filename: "foo.swift"))
    }

    @Test("pattern *.js matches .js files")
    func extensionPattern() {
        #expect(EditorConfig.matches(pattern: "*.js", filename: "app.js"))
        #expect(!EditorConfig.matches(pattern: "*.js", filename: "app.ts"))
    }

    @Test("brace pattern *.{js,ts} matches both")
    func bracePattern() {
        #expect(EditorConfig.matches(pattern: "*.{js,ts}", filename: "app.js"))
        #expect(EditorConfig.matches(pattern: "*.{js,ts}", filename: "app.ts"))
        #expect(!EditorConfig.matches(pattern: "*.{js,ts}", filename: "app.py"))
    }

    @Test("indent_style space maps to soft_tabs true")
    func indentStyleSpace() {
        let value = EditorConfig.convertValue(key: "indent_style", value: "space")
        #expect(value == .bool(true))
    }

    @Test("indent_style tab maps to soft_tabs false")
    func indentStyleTab() {
        let value = EditorConfig.convertValue(key: "indent_style", value: "tab")
        #expect(value == .bool(false))
    }

    @Test("indent_size maps to integer")
    func indentSize() {
        let value = EditorConfig.convertValue(key: "indent_size", value: "2")
        #expect(value == .integer(2))
    }

    @Test("key mapping covers standard keys")
    func keyMapping() {
        #expect(EditorConfig.mapToSW3TKey("indent_size") == "editor.tab_size")
        #expect(EditorConfig.mapToSW3TKey("indent_style") == "editor.soft_tabs")
        #expect(EditorConfig.mapToSW3TKey("charset") == "editor.encoding")
        #expect(EditorConfig.mapToSW3TKey("unknown_key") == nil)
    }
}
