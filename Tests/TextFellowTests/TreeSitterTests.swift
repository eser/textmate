import Testing
@testable import TextFellow

@Suite("TreeSitterHighlighter")
struct TreeSitterTests {
    @Test("parse JSON produces tokens")
    func parseJSON() {
        let registry = GrammarRegistry.shared
        guard let highlighter = registry.highlighter(forExtension: "json") else {
            Issue.record("No JSON grammar registered")
            return
        }

        let source = """
        {"name": "TextFellow", "version": 1, "active": true}
        """

        let tokens = highlighter.highlight(in: 0..<source.utf8.count, source: source)
        #expect(!tokens.isEmpty, "Expected tokens from JSON parse")

        // Should have tokens for braces, strings, numbers, etc.
        let scopes = Set(tokens.map(\.scope))
        #expect(scopes.contains("string_content"), "Expected string_content tokens, got: \(scopes)")
    }

    @Test("parse C produces tokens")
    func parseC() {
        guard let highlighter = GrammarRegistry.shared.highlighter(forExtension: "c") else {
            Issue.record("No C grammar")
            return
        }

        let source = """
        int main(int argc, char *argv[]) {
            return 0;
        }
        """

        let tokens = highlighter.highlight(in: 0..<source.utf8.count, source: source)
        #expect(!tokens.isEmpty, "Expected tokens from C parse")
    }

    @Test("parse JavaScript produces tokens")
    func parseJS() {
        guard let highlighter = GrammarRegistry.shared.highlighter(forExtension: "js") else {
            Issue.record("No JS grammar")
            return
        }

        let source = """
        const greeting = "hello";
        console.log(greeting);
        """

        let tokens = highlighter.highlight(in: 0..<source.utf8.count, source: source)
        #expect(!tokens.isEmpty)
    }

    @Test("parse Python produces tokens")
    func parsePython() {
        guard let highlighter = GrammarRegistry.shared.highlighter(forExtension: "py") else {
            Issue.record("No Python grammar")
            return
        }

        let source = """
        def hello(name):
            print(f"Hello, {name}!")
        """

        let tokens = highlighter.highlight(in: 0..<source.utf8.count, source: source)
        #expect(!tokens.isEmpty)
    }

    @Test("incremental edit marks dirty")
    func incrementalEdit() {
        guard let highlighter = GrammarRegistry.shared.highlighter(forExtension: "json") else {
            Issue.record("No JSON grammar")
            return
        }

        let source1 = """
        {"key": "value"}
        """
        _ = highlighter.highlight(in: 0..<source1.utf8.count, source: source1)

        // Simulate an edit
        highlighter.didEdit(at: 8..<13, delta: 2)

        let source2 = """
        {"key": "new value"}
        """
        let tokens = highlighter.highlight(in: 0..<source2.utf8.count, source: source2)
        #expect(!tokens.isEmpty, "Re-parse after edit should produce tokens")
    }

    @Test("highlight range returns only relevant tokens")
    func rangeFiltering() {
        guard let highlighter = GrammarRegistry.shared.highlighter(forExtension: "json") else {
            Issue.record("No JSON grammar")
            return
        }

        let source = """
        {"a": 1, "b": 2, "c": 3}
        """

        // Request only a subset
        let allTokens = highlighter.highlight(in: 0..<source.utf8.count, source: source)
        let partialTokens = highlighter.highlight(in: 0..<10, source: source)

        #expect(partialTokens.count <= allTokens.count, "Partial range should return fewer or equal tokens")
    }

    @Test("PlainTextHighlighter returns empty")
    func plainText() {
        let h = PlainTextHighlighter()
        let tokens = h.highlight(in: 0..<10, source: "hello world")
        #expect(tokens.isEmpty)
        #expect(h.language == "text.plain")
    }
}
