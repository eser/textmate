// SW³ TextFellow — Language Registry
// SPDX-License-Identifier: GPL-3.0-or-later
//
// In TextMate, grammar-to-file mapping comes from bundles:
// each .tmLanguage declares fileTypes and firstLineMatch.
// This registry is data-driven, not hardcoded.

import Foundation

/// A registered language with its detection rules.
public struct LanguageDefinition: Sendable, Identifiable {
    public let id: String            // e.g., "source.swift"
    public let name: String          // e.g., "Swift"
    public let fileExtensions: [String] // e.g., ["swift"]
    public let filePatterns: [String]  // e.g., ["Makefile", "Dockerfile"]
    public let firstLinePattern: String? // regex for first-line detection (e.g., "#!/usr/bin/env python")

    public init(
        id: String,
        name: String,
        fileExtensions: [String] = [],
        filePatterns: [String] = [],
        firstLinePattern: String? = nil
    ) {
        self.id = id
        self.name = name
        self.fileExtensions = fileExtensions
        self.filePatterns = filePatterns
        self.firstLinePattern = firstLinePattern
    }
}

/// Data-driven registry for language detection.
///
/// Languages are registered by bundles at load time.
/// Detection precedence: exact filename match → file extension → first line.
///
/// ```
///  Bundle loads grammar → registers LanguageDefinition
///       │
///       ▼
///  LanguageRegistry.detect(filename, firstLine)
///       │
///       ├─ exact filename match ("Makefile" → Make)
///       ├─ extension match (".swift" → Swift)
///       └─ first line match ("#!/usr/bin/env ruby" → Ruby)
/// ```
public final class LanguageRegistry: @unchecked Sendable {
    private var languages: [LanguageDefinition] = []
    private var extensionIndex: [String: LanguageDefinition] = [:]
    private var patternIndex: [String: LanguageDefinition] = [:]

    public init() {
        // Register built-in defaults. Bundles will add more at load time.
        registerDefaults()
    }

    /// Register a language definition (called by bundle loader).
    public func register(_ language: LanguageDefinition) {
        languages.append(language)
        for ext in language.fileExtensions {
            extensionIndex[ext.lowercased()] = language
        }
        for pattern in language.filePatterns {
            patternIndex[pattern] = language
        }
    }

    /// Detect the language for a given filename and optional first line.
    public func detect(filename: String, firstLine: String? = nil) -> LanguageDefinition? {
        // 1. Exact filename match (Makefile, Dockerfile, etc.)
        if let match = patternIndex[filename] {
            return match
        }

        // 2. File extension match
        let ext = (filename as NSString).pathExtension.lowercased()
        if !ext.isEmpty, let match = extensionIndex[ext] {
            return match
        }

        // 3. First line pattern match (shebang, modeline)
        if let firstLine, !firstLine.isEmpty {
            for lang in languages {
                if let pattern = lang.firstLinePattern,
                   firstLine.range(of: pattern, options: .regularExpression) != nil {
                    return lang
                }
            }
        }

        return nil
    }

    /// Get the display name for a file, or "Plain Text" if unknown.
    public func displayName(for filename: String, firstLine: String? = nil) -> String {
        detect(filename: filename, firstLine: firstLine)?.name ?? "Plain Text"
    }

    /// All registered languages, sorted by name.
    public var allLanguages: [LanguageDefinition] {
        languages.sorted { $0.name < $1.name }
    }

    // MARK: - Built-in defaults

    /// Minimal set of built-in language definitions.
    /// Real detection comes from bundles — these are just bootstrapping defaults
    /// so the editor isn't completely empty before bundles load.
    private func registerDefaults() {
        let defaults: [LanguageDefinition] = [
            LanguageDefinition(id: "source.swift", name: "Swift", fileExtensions: ["swift"]),
            LanguageDefinition(id: "source.js", name: "JavaScript", fileExtensions: ["js", "mjs", "cjs"]),
            LanguageDefinition(id: "source.ts", name: "TypeScript", fileExtensions: ["ts", "mts", "cts"]),
            LanguageDefinition(id: "source.tsx", name: "TypeScript (TSX)", fileExtensions: ["tsx"]),
            LanguageDefinition(id: "source.jsx", name: "JavaScript (JSX)", fileExtensions: ["jsx"]),
            LanguageDefinition(id: "source.python", name: "Python", fileExtensions: ["py", "pyw"], firstLinePattern: "^#!.*\\bpython"),
            LanguageDefinition(id: "source.ruby", name: "Ruby", fileExtensions: ["rb", "rake", "gemspec"], filePatterns: ["Rakefile", "Gemfile"], firstLinePattern: "^#!.*\\bruby"),
            LanguageDefinition(id: "source.rust", name: "Rust", fileExtensions: ["rs"]),
            LanguageDefinition(id: "source.go", name: "Go", fileExtensions: ["go"]),
            LanguageDefinition(id: "source.c", name: "C", fileExtensions: ["c", "h"]),
            LanguageDefinition(id: "source.cpp", name: "C++", fileExtensions: ["cpp", "cc", "cxx", "hpp", "hxx"]),
            LanguageDefinition(id: "source.objc", name: "Objective-C", fileExtensions: ["m"]),
            LanguageDefinition(id: "source.objcpp", name: "Objective-C++", fileExtensions: ["mm"]),
            LanguageDefinition(id: "source.metal", name: "Metal", fileExtensions: ["metal"]),
            LanguageDefinition(id: "source.json", name: "JSON", fileExtensions: ["json"]),
            LanguageDefinition(id: "source.toml", name: "TOML", fileExtensions: ["toml"]),
            LanguageDefinition(id: "source.yaml", name: "YAML", fileExtensions: ["yaml", "yml"]),
            LanguageDefinition(id: "text.html", name: "HTML", fileExtensions: ["html", "htm"]),
            LanguageDefinition(id: "source.css", name: "CSS", fileExtensions: ["css"]),
            LanguageDefinition(id: "source.scss", name: "SCSS", fileExtensions: ["scss"]),
            LanguageDefinition(id: "text.markdown", name: "Markdown", fileExtensions: ["md", "markdown"]),
            LanguageDefinition(id: "source.shell", name: "Shell", fileExtensions: ["sh", "bash", "zsh"], filePatterns: [".bashrc", ".zshrc", ".profile"], firstLinePattern: "^#!.*\\b(ba|z)?sh"),
            LanguageDefinition(id: "source.makefile", name: "Makefile", filePatterns: ["Makefile", "GNUmakefile", "makefile"]),
            LanguageDefinition(id: "source.dockerfile", name: "Dockerfile", filePatterns: ["Dockerfile"], firstLinePattern: "^FROM\\s"),
            LanguageDefinition(id: "source.xml", name: "XML", fileExtensions: ["xml", "plist", "svg"]),
            LanguageDefinition(id: "source.sql", name: "SQL", fileExtensions: ["sql"]),
            LanguageDefinition(id: "source.java", name: "Java", fileExtensions: ["java"]),
            LanguageDefinition(id: "source.kotlin", name: "Kotlin", fileExtensions: ["kt", "kts"]),
            LanguageDefinition(id: "source.lua", name: "Lua", fileExtensions: ["lua"], firstLinePattern: "^#!.*\\blua"),
            LanguageDefinition(id: "source.zig", name: "Zig", fileExtensions: ["zig"]),
        ]
        for lang in defaults {
            register(lang)
        }
    }
}
