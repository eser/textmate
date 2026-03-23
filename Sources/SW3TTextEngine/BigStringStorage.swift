// SW³ TextFellow — BigString TextStorage Conformance
// SPDX-License-Identifier: GPL-3.0-or-later

// BigString lives in the unstable _RopeModule. This is the ONLY file
// that imports it. If the API breaks, only this file changes.

// Note: As of swift-collections 1.1.x, BigString may not yet be
// publicly available. This implementation uses String as a temporary
// backing store with the same protocol surface. When BigString
// stabilizes, swap the backing store — no other file changes.

/// Concrete TextStorage implementation.
///
/// Currently backed by String (temporary). Will migrate to BigString
/// from swift-collections when _RopeModule stabilizes.
///
/// The TextStorage protocol ensures this is the only file that
/// needs to change for the migration.
public struct StringTextStorage: TextStorage, Sendable {
    private var _text: String

    public init(_ text: String = "") {
        self._text = text
    }

    // MARK: - TextStorage conformance

    public typealias Index = Int

    public mutating func insert(_ string: String, at index: Int) {
        let stringIndex = _text.utf8Index(at: index)
        _text.insert(contentsOf: string, at: stringIndex)
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
        guard !_text.isEmpty else { return 1 }
        var count = 1
        for char in _text {
            if char == "\n" { count += 1 }
        }
        return count
    }

    public var count: Int {
        _text.utf8.count
    }

    public func line(at lineNumber: Int) -> String {
        let lines = _text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lineNumber >= 0, lineNumber < lines.count else { return "" }
        return String(lines[lineNumber])
    }

    public func utf16Offset(for index: Int) -> Int {
        let stringIndex = _text.utf8Index(at: index)
        return _text.utf16.distance(from: _text.utf16.startIndex, to: stringIndex)
    }

    public func snapshot() -> TextStorageSnapshot {
        TextStorageSnapshot(text: _text, lineCount: lineCount)
    }

    public var text: String { _text }

    public var startIndex: Int { 0 }

    public var endIndex: Int { _text.utf8.count }

    public func index(at offset: Int) -> Int { offset }
}

// MARK: - String UTF-8 index helpers

extension String {
    /// Convert a UTF-8 byte offset to a String.Index.
    func utf8Index(at offset: Int) -> String.Index {
        utf8.index(utf8.startIndex, offsetBy: offset)
    }
}
