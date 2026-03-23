// SW³ TextFellow — SW3TSyntax
// SPDX-License-Identifier: GPL-3.0-or-later

import SW3TTextEngine

/// Unified protocol for syntax highlighting backends.
///
/// Two implementations:
/// - `TreeSitterHighlighter` — primary, incremental parsing
/// - `TextMateHighlighter` — fallback, Onigmo regex for .tmLanguage grammars
public protocol SyntaxHighlighter: Sendable {
    /// Produce highlight tokens for the given range.
    func highlight(in range: Range<Int>, storage: any TextStorage) -> [HighlightToken]

    /// Notify the highlighter that an edit occurred, so it can perform
    /// incremental re-parse.
    func didEdit(at range: Range<Int>, delta: Int)
}

/// A single highlighted span with scope and color info.
public struct HighlightToken: Sendable, Equatable {
    public let range: Range<Int>
    public let scope: String

    public init(range: Range<Int>, scope: String) {
        self.range = range
        self.scope = scope
    }
}

/// Placeholder: no-op highlighter for plain text files.
public struct PlainTextHighlighter: SyntaxHighlighter {
    public init() {}

    public func highlight(in range: Range<Int>, storage: any TextStorage) -> [HighlightToken] {
        []
    }

    public func didEdit(at range: Range<Int>, delta: Int) {}
}
