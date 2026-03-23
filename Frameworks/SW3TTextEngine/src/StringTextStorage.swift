// SW³ TextFellow — String-backed TextStorage
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Temporary implementation using String as backing store.
// When BigString from swift-collections stabilizes (_RopeModule),
// swap this file — no other code changes needed.

/// String-backed TextStorage. Works correctly for all sizes but
/// O(n) for insertions/deletions in the middle. Good enough for
/// files under ~100K lines. BigString (B-tree rope) will replace
/// this for O(log n) performance on large documents.
public struct StringTextStorage: TextStorage, Sendable {
    private var _text: String

    public init(_ text: String = "") {
        self._text = text
    }

    public typealias Index = Int

    public mutating func insert(_ string: String, at index: Int) {
        let si = _text.utf8Index(at: index)
        _text.insert(contentsOf: string, at: si)
    }

    public mutating func delete(range: Range<Int>) {
        let start = _text.utf8Index(at: range.lowerBound)
        let end = _text.utf8Index(at: range.upperBound)
        _text.removeSubrange(start..<end)
    }

    public func substring(range: Range<Int>) -> String {
        let start = _text.utf8Index(at: range.lowerBound)
        let end = _text.utf8Index(at: range.upperBound)
        return String(_text[start..<end])
    }

    public var lineCount: Int {
        _text.isEmpty ? 1 : _text.reduce(1) { $0 + ($1 == "\n" ? 1 : 0) }
    }

    public var count: Int { _text.utf8.count }
    public var text: String { _text }

    public func line(at lineNumber: Int) -> String {
        let lines = _text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lineNumber >= 0, lineNumber < lines.count else { return "" }
        return String(lines[lineNumber])
    }

    public func utf16Offset(for index: Int) -> Int {
        let si = _text.utf8Index(at: index)
        return _text.utf16.distance(from: _text.utf16.startIndex, to: si)
    }

    public func snapshot() -> TextStorageSnapshot {
        TextStorageSnapshot(text: _text, lineCount: lineCount)
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { _text.utf8.count }
    public func index(at offset: Int) -> Int { offset }
}

extension String {
    func utf8Index(at offset: Int) -> String.Index {
        utf8.index(utf8.startIndex, offsetBy: offset)
    }
}
