// SW³ TextFellow — TextEditSession Tests
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import SW3TTextEngine

// Tests run on TextEngineActor since TextEditSession is actor-isolated.

@Test @TextEngineActor
func sessionInsertAndRead() {
    let session = TextEditSession(text: "Hello")
    session.insert(" world", at: 5)
    #expect(session.text == "Hello world")
}

@Test @TextEngineActor
func sessionDeleteAndRead() {
    let session = TextEditSession(text: "Hello world")
    session.delete(range: 5..<11)
    #expect(session.text == "Hello")
}

@Test @TextEngineActor
func sessionUndoRestoresPreviousState() {
    let session = TextEditSession(text: "original")
    session.insert(" added", at: 8)
    #expect(session.text == "original added")

    let snap = session.undo()
    #expect(snap != nil)
    #expect(session.text == "original")
}

@Test @TextEngineActor
func sessionRedoRestoresUndoneState() {
    let session = TextEditSession(text: "base")
    session.insert("!", at: 4)
    #expect(session.text == "base!")

    _ = session.undo()
    #expect(session.text == "base")

    let snap = session.redo()
    #expect(snap != nil)
    #expect(session.text == "base!")
}

@Test @TextEngineActor
func sessionUndoAtRootReturnsNil() {
    let session = TextEditSession(text: "untouched")
    let snap = session.undo()
    #expect(snap == nil)
    #expect(session.text == "untouched")
}

@Test @TextEngineActor
func sessionRedoWithNothingUndoneReturnsNil() {
    let session = TextEditSession(text: "test")
    session.insert("!", at: 4)
    let snap = session.redo()
    #expect(snap == nil)
}

@Test @TextEngineActor
func sessionOperationLogRecordsAllMutations() {
    let session = TextEditSession(text: "")
    session.insert("A", at: 0)
    session.insert("B", at: 1)
    session.delete(range: 0..<1)
    #expect(session.operationCount == 3)
}

@Test @TextEngineActor
func sessionSnapshotIsIndependentOfFutureMutations() {
    let session = TextEditSession(text: "before")
    let snap = session.snapshot()
    session.insert(" after", at: 6)

    #expect(snap.text == "before")
    #expect(session.text == "before after")
}

@Test @TextEngineActor
func sessionLineCount() {
    let session = TextEditSession(text: "line1\nline2\nline3")
    #expect(session.lineCount == 3)
    #expect(session.line(at: 1) == "line2")
}
