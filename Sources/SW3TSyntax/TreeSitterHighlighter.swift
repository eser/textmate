// SW³ TextFellow — Tree-sitter Highlighter
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SW3TTextEngine

/// SyntaxHighlighter implementation backed by tree-sitter.
///
/// ```
///  Tree-sitter Pipeline:
///
///  Source text ──► TSParser.parse() ──► TSTree (syntax tree)
///       │                                  │
///       │  on edit:                         │
///       └──► TSParser.edit() ──► incremental re-parse
///                                          │
///  TSTree ──► TSTreeCursor walk ──► TSNode ranges
///       │
///       ▼
///  scope mapping ──► [HighlightToken]
/// ```
///
/// **Re-parse strategy** (configurable):
/// - Default: debounced (50ms after last keystroke)
/// - Optional: async background (re-parse on every edit)
///
/// **Timeout:** 2 seconds. If parser hangs, fall back to TextMate grammar.
public final class TreeSitterHighlighter: SyntaxHighlighter, @unchecked Sendable {
    /// The language this highlighter is configured for.
    public let language: String

    /// Re-parse mode.
    public enum ParseMode: Sendable {
        /// Re-parse 50ms after the last edit. Default.
        case debounced(interval: TimeInterval = 0.05)
        /// Re-parse on background task after every edit.
        case async
    }

    /// Maximum parser execution time before timeout (seconds).
    public let parserTimeout: TimeInterval

    private let parseMode: ParseMode
    private var cachedTokens: [HighlightToken] = []
    private var isDirty: Bool = true
    private var debounceWorkItem: DispatchWorkItem?

    /// Whether tree-sitter parsing timed out and we should fall back.
    public private(set) var didTimeout: Bool = false

    public init(
        language: String,
        parseMode: ParseMode = .debounced(),
        parserTimeout: TimeInterval = 2.0
    ) {
        self.language = language
        self.parseMode = parseMode
        self.parserTimeout = parserTimeout
    }

    // MARK: - SyntaxHighlighter

    public func highlight(in range: Range<Int>, storage: any TextStorage) -> [HighlightToken] {
        if isDirty {
            reparse(storage: storage)
        }

        // Return cached tokens that intersect the requested range
        return cachedTokens.filter { token in
            token.range.lowerBound < range.upperBound &&
            token.range.upperBound > range.lowerBound
        }
    }

    public func didEdit(at range: Range<Int>, delta: Int) {
        isDirty = true

        switch parseMode {
        case .debounced(let interval):
            debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.isDirty = true
            }
            debounceWorkItem = workItem
            DispatchQueue.global(qos: .userInteractive).asyncAfter(
                deadline: .now() + interval,
                execute: workItem
            )

        case .async:
            // In async mode, the next highlight() call triggers re-parse
            break
        }
    }

    // MARK: - Private

    private func reparse(storage: any TextStorage) {
        // TODO: When tree-sitter C runtime is integrated:
        //
        // 1. Create/update TSParser with the language grammar
        // 2. Call ts_parser_parse_string() with storage.text
        // 3. Walk the tree with TSTreeCursor
        // 4. Map node types to scope names via highlight queries
        // 5. Produce [HighlightToken] array
        //
        // For now, produce empty tokens (plain text rendering).
        // The protocol boundary means the renderer works regardless.

        cachedTokens = []
        isDirty = false
    }
}

// MARK: - Grammar Registry

/// Registry for available tree-sitter grammars.
///
/// Maps file extensions / language identifiers to grammar availability.
/// When a grammar is available, TreeSitterHighlighter is used.
/// When not, falls back to TextMateHighlighter.
public final class GrammarRegistry: Sendable {
    /// Known tree-sitter grammar availability by language.
    /// This will be populated from bundled grammar .dylib/.so files.
    private let available: Set<String>

    public init(availableLanguages: Set<String> = []) {
        self.available = availableLanguages
    }

    /// Check if a tree-sitter grammar is available for this language.
    public func hasTreeSitterGrammar(for language: String) -> Bool {
        available.contains(language)
    }

    /// Create the appropriate highlighter for a file.
    ///
    /// Selection logic:
    /// 1. tree-sitter grammar exists → TreeSitterHighlighter
    /// 2. TextMate grammar exists → TextMateHighlighter (not yet implemented)
    /// 3. Neither → PlainTextHighlighter
    public func highlighter(for language: String) -> any SyntaxHighlighter {
        if hasTreeSitterGrammar(for: language) {
            return TreeSitterHighlighter(language: language)
        }
        // TODO: Check for TextMate grammar (Phase 2.2)
        return PlainTextHighlighter()
    }
}
