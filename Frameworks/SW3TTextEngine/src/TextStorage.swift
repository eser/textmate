// SW³ TextFellow — TextStorage Protocol
// SPDX-License-Identifier: GPL-3.0-or-later

/// Core abstraction for text content. Every module talks to this protocol —
/// never directly to BigString or any concrete implementation.
public protocol TextStorage: Sendable {
    associatedtype Index: Comparable & Sendable

    mutating func insert(_ string: String, at index: Index)
    mutating func delete(range: Range<Index>)
    func substring(range: Range<Index>) -> String

    var lineCount: Int { get }
    var count: Int { get }
    var text: String { get }

    func line(at lineNumber: Int) -> String
    func utf16Offset(for index: Index) -> Int
    func snapshot() -> TextStorageSnapshot

    var startIndex: Index { get }
    var endIndex: Index { get }
    func index(at offset: Int) -> Index
}

/// Immutable COW snapshot of text state. O(1) to create.
public struct TextStorageSnapshot: Sendable {
    public let text: String
    public let lineCount: Int
    public init(text: String, lineCount: Int) {
        self.text = text
        self.lineCount = lineCount
    }
}
