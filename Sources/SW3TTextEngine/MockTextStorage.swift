// SW³ TextFellow — Mock TextStorage for Testing
// SPDX-License-Identifier: GPL-3.0-or-later

/// A minimal TextStorage implementation for use in tests.
/// Exported publicly so test targets across modules can use it.
public struct MockTextStorage: TextStorage, Sendable {
    private var _text: String

    public init(_ text: String = "Hello, world!") {
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
        _text.isEmpty ? 1 : _text.filter { $0 == "\n" }.count + 1
    }

    public var count: Int { _text.utf8.count }

    public func line(at lineNumber: Int) -> String {
        let lines = _text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lineNumber >= 0, lineNumber < lines.count else { return "" }
        return String(lines[lineNumber])
    }

    public func utf16Offset(for index: Int) -> Int { index }

    public func snapshot() -> TextStorageSnapshot {
        TextStorageSnapshot(text: _text, lineCount: lineCount)
    }

    public var text: String { _text }
    public var startIndex: Int { 0 }
    public var endIndex: Int { _text.utf8.count }
    public func index(at offset: Int) -> Int { offset }
}
