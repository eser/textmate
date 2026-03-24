// SW³ TextFellow — Rope-backed TextStorage
// SPDX-License-Identifier: GPL-3.0-or-later
//
// O(log n) text storage using the Rope data structure.
// Drop-in replacement for StringTextStorage on large files.

/// Rope-backed TextStorage. O(log n) for insert/delete in the middle.
/// Designed for files >100K lines where StringTextStorage's O(n) becomes
/// a bottleneck.
public struct RopeTextStorage: TextStorage, Sendable {
    private var _rope: Rope

    public init(_ text: String = "") {
        self._rope = Rope(text)
    }

    public typealias Index = Int

    public mutating func insert(_ string: String, at index: Int) {
        _rope = _rope.inserting(string, at: index)
    }

    public mutating func delete(range: Range<Int>) {
        _rope = _rope.deleting(range: range)
    }

    public func substring(range: Range<Int>) -> String {
        _rope.substring(range: range)
    }

    public var lineCount: Int { _rope.lineCount }
    public var count: Int { _rope.byteCount }
    public var text: String { _rope.text }

    public func line(at lineNumber: Int) -> String {
        _rope.line(at: lineNumber)
    }

    public func utf16Offset(for index: Int) -> Int {
        // Extract the substring up to `index` and measure its UTF-16 length.
        let prefix = _rope.substring(range: 0..<index)
        return prefix.utf16.count
    }

    public func snapshot() -> TextStorageSnapshot {
        TextStorageSnapshot(text: _rope.text, lineCount: _rope.lineCount)
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { _rope.byteCount }
    public func index(at offset: Int) -> Int { offset }
}
