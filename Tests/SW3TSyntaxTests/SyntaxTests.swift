import Testing
@testable import SW3TSyntax
import SW3TTextEngine

@Test func plainTextHighlighterReturnsNoTokens() {
    let highlighter = PlainTextHighlighter()
    let tokens = highlighter.highlight(in: 0..<10, storage: MockTextStorage())
    #expect(tokens.isEmpty)
}

@Test func treeSitterHighlighterFallsBackGracefully() {
    // Without a real tree-sitter runtime, the highlighter produces
    // empty tokens — same as PlainTextHighlighter. This verifies
    // the protocol boundary works.
    let highlighter = TreeSitterHighlighter(language: "swift")
    let tokens = highlighter.highlight(in: 0..<10, storage: MockTextStorage("let x = 42"))
    // No grammar loaded → empty tokens (graceful fallback)
    #expect(tokens.isEmpty)
}

@Test func grammarRegistryFallsBackToPlainText() {
    let registry = GrammarRegistry(availableLanguages: ["rust"])

    // Language with grammar → TreeSitterHighlighter
    let rustHighlighter = registry.highlighter(for: "rust")
    #expect(rustHighlighter is TreeSitterHighlighter)

    // Language without grammar → PlainTextHighlighter
    let unknownHighlighter = registry.highlighter(for: "brainfuck")
    #expect(unknownHighlighter is PlainTextHighlighter)
}

@Test func treeSitterHighlighterMarksEditsAsDirty() {
    let highlighter = TreeSitterHighlighter(language: "swift")
    // Initial call triggers parse
    _ = highlighter.highlight(in: 0..<5, storage: MockTextStorage("hello"))
    // Edit notification
    highlighter.didEdit(at: 0..<1, delta: 1)
    // Next highlight should re-parse (isDirty = true)
    let tokens = highlighter.highlight(in: 0..<5, storage: MockTextStorage("xhello"))
    #expect(tokens.isEmpty) // still empty until real tree-sitter is integrated
}

// MARK: - Language Registry Tests

@Test func languageRegistryDetectsByExtension() {
    let registry = LanguageRegistry()
    let lang = registry.detect(filename: "main.swift")
    #expect(lang?.name == "Swift")
    #expect(lang?.id == "source.swift")
}

@Test func languageRegistryDetectsByFilename() {
    let registry = LanguageRegistry()
    let lang = registry.detect(filename: "Makefile")
    #expect(lang?.name == "Makefile")
}

@Test func languageRegistryDetectsByFirstLine() {
    let registry = LanguageRegistry()
    let lang = registry.detect(filename: "script", firstLine: "#!/usr/bin/env python3")
    #expect(lang?.name == "Python")
}

@Test func languageRegistryReturnsNilForUnknown() {
    let registry = LanguageRegistry()
    let lang = registry.detect(filename: "data.xyz123")
    #expect(lang == nil)
}

@Test func languageRegistryDisplayNameFallback() {
    let registry = LanguageRegistry()
    #expect(registry.displayName(for: "test.swift") == "Swift")
    #expect(registry.displayName(for: "unknown.xyz") == "Plain Text")
}

@Test func languageRegistryCustomRegistration() {
    let registry = LanguageRegistry()
    registry.register(LanguageDefinition(
        id: "source.brainfuck",
        name: "Brainfuck",
        fileExtensions: ["bf", "b"]
    ))
    let lang = registry.detect(filename: "hello.bf")
    #expect(lang?.name == "Brainfuck")
}

@Test func highlightTokenEquality() {
    let t1 = HighlightToken(range: 0..<5, scope: "keyword")
    let t2 = HighlightToken(range: 0..<5, scope: "keyword")
    let t3 = HighlightToken(range: 0..<5, scope: "variable")
    #expect(t1 == t2)
    #expect(t1 != t3)
}
