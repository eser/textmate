// SW³ TextFellow — TextStorage Protocol
// SPDX-License-Identifier: GPL-3.0-or-later

/// The core abstraction for text content.
///
/// Every module in SW³ TextFellow talks to this protocol — never directly
/// to `BigString` or any concrete implementation. This isolates the
/// codebase from `_RopeModule` API instability and enables swapping
/// backends (e.g., Ropey via Rust FFI) by changing only the conformance.
///
/// ```
///   SW3TRenderer ──► ViewportProvider ──► TextStorage (protocol)
///   SW3TSyntax   ──► SyntaxHighlighter ──► TextStorage (protocol)
///   SW3TDocument ──► owns ──► TextStorage (protocol)
///                                              │
///                                    ┌─────────▼──────────┐
///                                    │ BigStringStorage    │
///                                    │ (concrete, private) │
///                                    └────────────────────┘
/// ```
public protocol TextStorage: Sendable {
    /// The type used for indexing into the text.
    associatedtype Index: Comparable & Sendable

    /// Insert a string at the given index.
    mutating func insert(_ string: String, at index: Index)

    /// Delete text in the given range.
    mutating func delete(range: Range<Index>)

    /// Return the substring for the given range.
    func substring(range: Range<Index>) -> String

    /// Total number of lines in the document.
    var lineCount: Int { get }

    /// Total number of UTF-8 bytes in the document.
    var count: Int { get }

    /// Return the content of a line by zero-based line number.
    func line(at lineNumber: Int) -> String

    /// Convert a storage index to a UTF-16 offset (for platform text input APIs).
    func utf16Offset(for index: Index) -> Int

    /// Create an immutable snapshot of the current state.
    /// O(1) via copy-on-write — just increments a reference count.
    func snapshot() -> TextStorageSnapshot

    /// The full text content as a String.
    var text: String { get }

    /// The start index.
    var startIndex: Index { get }

    /// The end index.
    var endIndex: Index { get }

    /// Convert an integer offset to an Index.
    func index(at offset: Int) -> Index
}

/// An immutable snapshot of text storage state.
///
/// Cheap to create (O(1) via COW), cheap to hold (structural sharing).
/// Used by the undo system to store states and by the renderer/parser
/// to read text without blocking the TextEngineActor.
public struct TextStorageSnapshot: Sendable {
    public let text: String
    public let lineCount: Int

    public init(text: String, lineCount: Int) {
        self.text = text
        self.lineCount = lineCount
    }
}
