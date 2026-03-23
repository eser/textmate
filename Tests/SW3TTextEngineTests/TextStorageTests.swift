// SW³ TextFellow — TextStorage Protocol Conformance Tests
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import SW3TTextEngine

// MARK: - StringTextStorage conformance tests

@Test func emptyStorageHasOneLineAndZeroCount() {
    let storage = StringTextStorage()
    #expect(storage.count == 0)
    #expect(storage.lineCount == 1)
    #expect(storage.text == "")
}

@Test func insertAtBeginning() {
    var storage = StringTextStorage()
    storage.insert("Hello", at: 0)
    #expect(storage.text == "Hello")
    #expect(storage.count == 5)
    #expect(storage.lineCount == 1)
}

@Test func insertAtEnd() {
    var storage = StringTextStorage("Hello")
    storage.insert(" world", at: 5)
    #expect(storage.text == "Hello world")
}

@Test func insertInMiddle() {
    var storage = StringTextStorage("Helo")
    storage.insert("l", at: 2)
    #expect(storage.text == "Hello")
}

@Test func insertMultipleLines() {
    var storage = StringTextStorage()
    storage.insert("line1\nline2\nline3", at: 0)
    #expect(storage.lineCount == 3)
    #expect(storage.line(at: 0) == "line1")
    #expect(storage.line(at: 1) == "line2")
    #expect(storage.line(at: 2) == "line3")
}

@Test func deleteRange() {
    var storage = StringTextStorage("Hello world")
    storage.delete(range: 5..<11) // delete " world"
    #expect(storage.text == "Hello")
}

@Test func deleteEntireContent() {
    var storage = StringTextStorage("Hello")
    storage.delete(range: 0..<5)
    #expect(storage.text == "")
    #expect(storage.count == 0)
    #expect(storage.lineCount == 1)
}

@Test func substringExtraction() {
    let storage = StringTextStorage("Hello world")
    let sub = storage.substring(range: 0..<5)
    #expect(sub == "Hello")
}

@Test func lineAccessByNumber() {
    let storage = StringTextStorage("first\nsecond\nthird")
    #expect(storage.line(at: 0) == "first")
    #expect(storage.line(at: 1) == "second")
    #expect(storage.line(at: 2) == "third")
}

@Test func lineAccessOutOfBoundsReturnsEmpty() {
    let storage = StringTextStorage("one line")
    #expect(storage.line(at: 1) == "")
    #expect(storage.line(at: -1) == "")
    #expect(storage.line(at: 999) == "")
}

@Test func snapshotIsImmutable() {
    var storage = StringTextStorage("before")
    let snap = storage.snapshot()
    storage.insert(" after", at: 6)

    #expect(snap.text == "before")
    #expect(storage.text == "before after")
}

@Test func startAndEndIndex() {
    let storage = StringTextStorage("Hello")
    #expect(storage.startIndex == 0)
    #expect(storage.endIndex == 5)
}

@Test func indexAtOffset() {
    let storage = StringTextStorage("Hello")
    #expect(storage.index(at: 3) == 3)
}

// MARK: - Unicode edge cases

@Test func unicodeEmoji() {
    var storage = StringTextStorage()
    storage.insert("Hello 🌍", at: 0)
    #expect(storage.lineCount == 1)
    #expect(storage.text == "Hello 🌍")
}

@Test func unicodeCJK() {
    var storage = StringTextStorage()
    storage.insert("你好世界", at: 0)
    #expect(storage.text == "你好世界")
    #expect(storage.lineCount == 1)
}

@Test func emptyLinesCounted() {
    let storage = StringTextStorage("\n\n\n")
    #expect(storage.lineCount == 4) // 3 newlines = 4 lines
}
