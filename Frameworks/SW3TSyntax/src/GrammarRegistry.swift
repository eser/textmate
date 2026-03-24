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

    /// Number of registered grammars.
    @objc public var registeredCount: Int { grammars.count }

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

        // JavaScript
        let jsLang: OpaquePointer = tree_sitter_javascript()
        register(name: "javascript", extensions: ["js", "mjs", "cjs", "jsx"], language: jsLang)

        // Python
        let pyLang: OpaquePointer = tree_sitter_python()
        register(name: "python", extensions: ["py", "pyw"], language: pyLang)

        // Go
        let goLang: OpaquePointer = tree_sitter_go()
        register(name: "go", extensions: ["go"], language: goLang)

        // Rust
        let rustLang: OpaquePointer = tree_sitter_rust()
        register(name: "rust", extensions: ["rs"], language: rustLang)

        // TypeScript
        let tsLang: OpaquePointer = tree_sitter_typescript()
        register(name: "typescript", extensions: ["ts", "mts", "cts"], language: tsLang)

        // HTML
        let htmlLang: OpaquePointer = tree_sitter_html()
        register(name: "html", extensions: ["html", "htm"], language: htmlLang)

        // CSS
        let cssLang: OpaquePointer = tree_sitter_css()
        register(name: "css", extensions: ["css"], language: cssLang)

        // Markdown
        let mdLang: OpaquePointer = tree_sitter_markdown()
        register(name: "markdown", extensions: ["md", "markdown"], language: mdLang)

        // YAML
        let yamlLang: OpaquePointer = tree_sitter_yaml()
        register(name: "yaml", extensions: ["yaml", "yml"], language: yamlLang)

        // Bash
        let bashLang: OpaquePointer = tree_sitter_bash()
        register(name: "bash", extensions: ["sh", "bash", "zsh"], language: bashLang)

        // TOML
        let tomlLang: OpaquePointer = tree_sitter_toml()
        register(name: "toml", extensions: ["toml"], language: tomlLang)
    }
}
