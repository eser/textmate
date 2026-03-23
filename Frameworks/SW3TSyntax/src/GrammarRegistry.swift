// SW³ TextFellow — Grammar Registry
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Registry of available tree-sitter grammars.
/// Maps file extensions to grammar entry points.
@objc(SW3TGrammarRegistry)
public final class GrammarRegistry: NSObject, @unchecked Sendable {
    @objc public static let shared = GrammarRegistry()

    /// Registered grammars: extension → (language name, TSLanguage pointer)
    private var grammars: [String: (name: String, language: OpaquePointer)] = [:]

    public override init() {
        super.init()
        registerBuiltinGrammars()
    }

    /// Register a tree-sitter grammar for the given file extensions.
    public func register(name: String, extensions: [String], language: OpaquePointer) {
        for ext in extensions {
            grammars[ext.lowercased()] = (name, language)
        }
    }

    /// Create a TreeSitterHighlighter for the given file extension, if available.
    public func highlighter(forExtension ext: String) -> TreeSitterHighlighter? {
        guard let grammar = grammars[ext.lowercased()] else { return nil }
        return TreeSitterHighlighter(language: grammar.name, tsLanguage: grammar.language)
    }

    /// Check if a tree-sitter grammar is available for this extension.
    @objc public func hasGrammar(forExtension ext: String) -> Bool {
        grammars[ext.lowercased()] != nil
    }

    /// All registered language names.
    @objc public var availableLanguages: [String] {
        Array(Set(grammars.values.map(\.name))).sorted()
    }

    // MARK: - Built-in grammars

    private func registerBuiltinGrammars() {
        // JSON
        let jsonLang: OpaquePointer = tree_sitter_json()
        register(name: "json", extensions: ["json", "jsonl"], language: jsonLang)

        // C
        let cLang: OpaquePointer = tree_sitter_c()
        register(name: "c", extensions: ["c", "h"], language: cLang)
    }
}
