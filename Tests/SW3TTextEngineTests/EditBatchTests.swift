// SW³ TextFellow — EditBatch Tests
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import SW3TTextEngine

@Test @TextEngineActor
func batchInsertMultipleCursors() {
    // Simulate 3 cursors each inserting "x" at positions 0, 5, 10
    let session = TextEditSession(text: "aaaaa|bbbbb|ccccc")

    var batch = EditBatch()
    batch.insert("x", at: 0)
    batch.insert("x", at: 6)  // after first "x" shifts things
    batch.insert("x", at: 12) // after two "x"s shift things
    session.apply(batch: batch)

    #expect(session.text == "xaaaaa|xbbbbb|xccccc")
}

@Test @TextEngineActor
func batchIsAtomicForUndo() {
    let session = TextEditSession(text: "original")

    var batch = EditBatch()
    batch.insert("A", at: 0)
    batch.insert("B", at: 2) // after "A" inserted, offset adjusts
    session.apply(batch: batch)

    // One undo should revert the entire batch
    let snap = session.undo()
    #expect(snap != nil)
    #expect(session.text == "original")
}

@Test @TextEngineActor
func emptyBatchIsNoOp() {
    let session = TextEditSession(text: "unchanged")
    let batch = EditBatch()
    session.apply(batch: batch)
    #expect(session.text == "unchanged")
    #expect(session.operationCount == 0)
}

@Test @TextEngineActor
func batchDeleteMultipleRanges() {
    // "xxHelloxxWorldxx" — delete "xx" at start and "xx" in middle
    // Offsets are in ORIGINAL document coordinates.
    // The batch engine adjusts for cumulative delta internally.
    let session = TextEditSession(text: "xxHelloxxWorldxx")

    var batch = EditBatch()
    batch.delete(range: 0..<2)   // remove leading "xx" (original offset 0..2)
    batch.delete(range: 7..<9)   // remove middle "xx" (original offset 7..9)
    session.apply(batch: batch)

    #expect(session.text == "HelloWorldxx")
}

@Test @TextEngineActor
func batchMixedInsertDelete() {
    // Delete then insert at the same position — offsets are adjusted
    // by cumulative delta. After deleting 6 chars at offset 5,
    // the document is "Hello" (5 bytes). To insert "!" at position 5
    // (end of "Hello"), the original offset should be 11 (end of original doc)
    // since delete already removed 5..<11.
    let session = TextEditSession(text: "Hello world")

    var batch = EditBatch()
    batch.delete(range: 5..<11) // delete " world"
    batch.insert("!", at: 11)   // insert at original end position → adjusted to 11-6=5
    session.apply(batch: batch)

    #expect(session.text == "Hello!")
}

@Test
func editBatchBuilderAPI() {
    var batch = EditBatch()
    #expect(batch.isEmpty)
    #expect(batch.count == 0)

    batch.insert("hello", at: 0)
    batch.delete(range: 5..<10)

    #expect(!batch.isEmpty)
    #expect(batch.count == 2)
}
