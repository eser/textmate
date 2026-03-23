import Testing
@testable import TextFellow

@Suite("TextEngine")
struct TextEngineTests {

    // MARK: - StringTextStorage

    @Test("insert at beginning")
    func insertBeginning() {
        var s = StringTextStorage("world")
        s.insert("hello ", at: 0)
        #expect(s.text == "hello world")
    }

    @Test("insert at end")
    func insertEnd() {
        var s = StringTextStorage("hello")
        s.insert(" world", at: 5)
        #expect(s.text == "hello world")
    }

    @Test("delete range")
    func deleteRange() {
        var s = StringTextStorage("hello world")
        s.delete(range: 5..<11)
        #expect(s.text == "hello")
    }

    @Test("line count")
    func lineCount() {
        let s = StringTextStorage("line1\nline2\nline3")
        #expect(s.lineCount == 3)
    }

    @Test("line at index")
    func lineAt() {
        let s = StringTextStorage("first\nsecond\nthird")
        #expect(s.line(at: 0) == "first")
        #expect(s.line(at: 1) == "second")
        #expect(s.line(at: 2) == "third")
    }

    @Test("snapshot preserves state")
    func snapshot() {
        var s = StringTextStorage("before")
        let snap = s.snapshot()
        s.insert(" after", at: 6)
        #expect(snap.text == "before")
        #expect(s.text == "before after")
    }

    @Test("empty storage has 1 line")
    func emptyLine() {
        let s = StringTextStorage("")
        #expect(s.lineCount == 1)
        #expect(s.count == 0)
    }

    // MARK: - EditBatch

    @Test("batch applies multiple inserts")
    func batchInserts() {
        var s = StringTextStorage("ac")
        var batch = EditBatch()
        batch.insert("b", at: 1)
        apply(batch: batch, to: &s)
        #expect(s.text == "abc")
    }

    @Test("batch applies insert and delete")
    func batchMixed() {
        var s = StringTextStorage("hello world")
        var batch = EditBatch()
        batch.delete(at: 5, length: 6)
        batch.insert("!", at: 5)
        apply(batch: batch, to: &s)
        #expect(s.text == "hello!")
    }

    // MARK: - TextEngineActor

    @Test("actor insert and read")
    func actorInsert() async {
        let engine = TextEngineActor(text: "hello")
        await engine.insert(" world", at: 5)
        let text = await engine.text
        #expect(text == "hello world")
    }

    @Test("actor undo")
    func actorUndo() async {
        let engine = TextEngineActor(text: "hello")
        await engine.insert(" world", at: 5)
        #expect(await engine.text == "hello world")
        await engine.undo()
        #expect(await engine.text == "hello")
    }

    @Test("actor redo")
    func actorRedo() async {
        let engine = TextEngineActor(text: "hello")
        await engine.insert(" world", at: 5)
        await engine.undo()
        await engine.redo()
        #expect(await engine.text == "hello world")
    }

    @Test("actor batch")
    func actorBatch() async {
        let engine = TextEngineActor(text: "ac")
        var batch = EditBatch()
        batch.insert("b", at: 1)
        await engine.apply(batch: batch)
        #expect(await engine.text == "abc")
        #expect(await engine.canUndo == true)
    }

    @Test("actor snapshot is independent")
    func actorSnapshot() async {
        let engine = TextEngineActor(text: "original")
        let snap = await engine.snapshot()
        await engine.insert(" modified", at: 8)
        #expect(snap.text == "original")
        #expect(await engine.text == "original modified")
    }
}
