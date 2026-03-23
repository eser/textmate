// SW³ TextFellow — TextEngine Actor
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Dedicated actor owning all mutable text state.
// Mutations are async, readers get immutable COW snapshots.

import Foundation

/// Actor that owns mutable text state. All mutations go through here.
/// Readers receive immutable snapshots — no locking needed.
///
/// ```
///                 ┌─────────────────────┐
///                 │  TextEngineActor     │
///  insert/delete─►│  (owns mutable)     │──► snapshot() ──► Renderer
///  (via batch)    │  StringTextStorage   │──► snapshot() ──► tree-sitter
///                 │  UndoStack           │──► snapshot() ──► Undo
///                 └─────────────────────┘
/// ```
public actor TextEngineActor {
    private var storage: StringTextStorage
    private var undoStack: [TextStorageSnapshot] = []
    private var redoStack: [TextStorageSnapshot] = []

    public init(text: String = "") {
        self.storage = StringTextStorage(text)
    }

    // MARK: - Mutations

    /// Apply a single insert.
    public func insert(_ text: String, at offset: Int) {
        pushUndo()
        storage.insert(text, at: offset)
    }

    /// Apply a single delete.
    public func delete(range: Range<Int>) {
        pushUndo()
        storage.delete(range: range)
    }

    /// Apply a batch of edits atomically (one undo entry).
    public func apply(batch: EditBatch) {
        guard !batch.isEmpty else { return }
        pushUndo()
        var s = storage
        TextFellow.apply(batch: batch, to: &s)
        storage = s
    }

    // MARK: - Undo/Redo

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(storage.snapshot())
        storage = StringTextStorage(previous.text)
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(storage.snapshot())
        storage = StringTextStorage(next.text)
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Read Access

    /// O(1) immutable snapshot for concurrent readers.
    public func snapshot() -> TextStorageSnapshot {
        storage.snapshot()
    }

    public var text: String { storage.text }
    public var lineCount: Int { storage.lineCount }
    public var count: Int { storage.count }

    public func line(at lineNumber: Int) -> String {
        storage.line(at: lineNumber)
    }

    // MARK: - Private

    private func pushUndo() {
        undoStack.append(storage.snapshot())
        redoStack.removeAll()
    }
}
