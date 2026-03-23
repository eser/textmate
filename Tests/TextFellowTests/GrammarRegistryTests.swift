import Testing
@testable import TextFellow

@Suite("GrammarRegistry")
struct GrammarRegistryTests {
    @Test("has JSON grammar")
    func jsonGrammar() {
        #expect(GrammarRegistry.shared.hasGrammar(forExtension: "json"))
    }

    @Test("has C grammar")
    func cGrammar() {
        #expect(GrammarRegistry.shared.hasGrammar(forExtension: "c"))
    }

    @Test("has JavaScript grammar")
    func jsGrammar() {
        #expect(GrammarRegistry.shared.hasGrammar(forExtension: "js"))
    }

    @Test("has Python grammar")
    func pythonGrammar() {
        #expect(GrammarRegistry.shared.hasGrammar(forExtension: "py"))
    }

    @Test("no grammar for unknown extension")
    func unknownExtension() {
        #expect(!GrammarRegistry.shared.hasGrammar(forExtension: "xyz"))
    }

    @Test("creates highlighter for JSON")
    func jsonHighlighter() {
        let h = GrammarRegistry.shared.highlighter(forExtension: "json")
        #expect(h != nil)
        #expect(h?.language == "json")
    }

    @Test("available languages includes all registered")
    func availableLanguages() {
        let langs = GrammarRegistry.shared.availableLanguages
        #expect(langs.contains("json"))
        #expect(langs.contains("c"))
        #expect(langs.contains("javascript"))
        #expect(langs.contains("python"))
    }
}
