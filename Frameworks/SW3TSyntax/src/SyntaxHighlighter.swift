// SW³ TextFellow — SyntaxHighlighter Protocol
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Unified protocol for syntax highlighting backends.
///
/// Two implementations:
/// - `TreeSitterHighlighter` — incremental parsing via tree-sitter
/// - TextMate grammars — existing Onigmo regex engine (default/fallback)
public protocol SyntaxHighlighter: Sendable {
    /// Produce highlight tokens for the given byte range.
    func highlight(in range: Range<Int>, source: String) -> [HighlightToken]

    /// Notify the highlighter that an edit occurred for incremental re-parse.
    func didEdit(at range: Range<Int>, delta: Int)

    /// The language identifier (e.g., "swift", "javascript").
    var language: String { get }
}

/// A single highlighted span with a scope name.
public struct HighlightToken: Sendable, Equatable {
    public let range: Range<Int>
    public let scope: String

    public init(range: Range<Int>, scope: String) {
        self.range = range
        self.scope = scope
    }
}

/// No-op highlighter for plain text files.
public struct PlainTextHighlighter: SyntaxHighlighter {
    public let language = "text.plain"
    public init() {}

    public func highlight(in range: Range<Int>, source: String) -> [HighlightToken] {
        []
    }

    public func didEdit(at range: Range<Int>, delta: Int) {}
}
