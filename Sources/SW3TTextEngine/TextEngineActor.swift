// SW³ TextFellow — TextEngineActor
// SPDX-License-Identifier: GPL-3.0-or-later

/// Dedicated global actor that owns all mutable text state.
///
/// ```
///  ┌──────────────────────────┐
///  │    TextEngineActor       │
///  │    (isolation domain)    │
///  │                          │
///  │  ┌────────────────────┐  │   insert/delete
///  │  │ StringTextStorage  │◄─┼── (async calls)
///  │  └────────────────────┘  │
///  │  ┌────────────────────┐  │   snapshot()
///  │  │ OperationLog       │──┼──► (COW, sent to renderer/parser)
///  │  └────────────────────┘  │
///  │  ┌────────────────────┐  │
///  │  │ UndoTree           │  │
///  │  └────────────────────┘  │
///  └──────────────────────────┘
/// ```
///
/// **Why a dedicated actor (not @MainActor)?**
/// Keeps text mutations off the main thread. The main actor handles
/// UI events; TextEngineActor handles document state. Snapshots
/// (COW, O(1)) are the communication channel between them.
@globalActor
public actor TextEngineActor {
    public static let shared = TextEngineActor()
}

/// A document's text editing session, isolated to `TextEngineActor`.
///
/// All mutations go through this type. Readers get immutable snapshots.
@TextEngineActor
public final class TextEditSession {
    private var storage: StringTextStorage
    private let operationLog: OperationLog
    private let undoManager: LinearUndoManager

    public init(text: String = "") {
        self.storage = StringTextStorage(text)
        self.operationLog = OperationLog()
        self.undoManager = LinearUndoManager()
    }

    // MARK: - Mutations

    /// Insert text at the given UTF-8 byte offset.
    public func insert(_ text: String, at offset: Int) {
        let snapBefore = storage.snapshot()
        let ts = operationLog.nextTimestamp()
        let op = EditOperation.insert(offset: offset, text: text, timestamp: ts)

        storage.insert(text, at: offset)

        operationLog.record(op)
        undoManager.record(operation: op, snapshot: snapBefore)
    }

    /// Delete text in the given UTF-8 byte range.
    public func delete(range: Range<Int>) {
        let snapBefore = storage.snapshot()
        let deletedText = storage.substring(range: range)
        let ts = operationLog.nextTimestamp()
        let op = EditOperation.delete(
            offset: range.lowerBound,
            length: range.count,
            deletedText: deletedText,
            timestamp: ts
        )

        storage.delete(range: range)

        operationLog.record(op)
        undoManager.record(operation: op, snapshot: snapBefore)
    }

    // MARK: - Batch Mutations

    /// Apply a batch of operations atomically.
    ///
    /// All operations execute in a single actor call. One snapshot
    /// before, one undo entry for the entire batch. Operations are
    /// applied in order with offset adjustment — each operation's
    /// offset accounts for the cumulative effect of prior operations
    /// in the batch.
    ///
    /// Use this for multi-cursor edits, find-and-replace, and large pastes.
    public func apply(batch: EditBatch) {
        guard !batch.isEmpty else { return }

        let snapBefore = storage.snapshot()
        var cumulativeDelta = 0

        for batchOp in batch.operations {
            let ts = operationLog.nextTimestamp()
            switch batchOp {
            case .insert(let offset, let text):
                let adjustedOffset = offset + cumulativeDelta
                let op = EditOperation.insert(offset: adjustedOffset, text: text, timestamp: ts)
                storage.insert(text, at: adjustedOffset)
                operationLog.record(op)
                cumulativeDelta += text.utf8.count

            case .delete(let range):
                let adjustedRange = (range.lowerBound + cumulativeDelta)..<(range.upperBound + cumulativeDelta)
                let deletedText = storage.substring(range: adjustedRange)
                let op = EditOperation.delete(
                    offset: adjustedRange.lowerBound,
                    length: adjustedRange.count,
                    deletedText: deletedText,
                    timestamp: ts
                )
                storage.delete(range: adjustedRange)
                operationLog.record(op)
                cumulativeDelta -= adjustedRange.count
            }
        }

        // Record as a single undo unit — undoing restores snapBefore
        let groupOp = EditOperation.insert(offset: 0, text: "[batch:\(batch.count)]", timestamp: operationLog.nextTimestamp())
        undoManager.record(operation: groupOp, snapshot: snapBefore)
    }

    // MARK: - Reading (produces snapshots for other actors)

    /// Create an immutable snapshot of the current text state.
    /// Safe to send to any other actor or thread.
    public func snapshot() -> TextStorageSnapshot {
        storage.snapshot()
    }

    /// The current text content.
    public var text: String {
        storage.text
    }

    /// Number of lines.
    public var lineCount: Int {
        storage.lineCount
    }

    /// Get a line by number.
    public func line(at lineNumber: Int) -> String {
        storage.line(at: lineNumber)
    }

    /// Total UTF-8 byte count.
    public var count: Int {
        storage.count
    }

    // MARK: - Undo/Redo

    /// Undo the last operation, restoring the previous state.
    /// Returns the restored snapshot, or nil if nothing to undo.
    public func undo() -> TextStorageSnapshot? {
        guard let snap = undoManager.undo() else { return nil }
        storage = StringTextStorage(snap.text)
        return snap
    }

    /// Redo the last undone operation by re-applying it.
    /// Returns the new snapshot after re-application, or nil if nothing to redo.
    public func redo() -> TextStorageSnapshot? {
        guard let op = undoManager.peekRedo() else { return nil }
        _ = undoManager.redo() // move entry back to undo stack

        // Re-apply the operation
        switch op {
        case .insert(let offset, let text, _):
            storage.insert(text, at: offset)
        case .delete(let offset, let length, _, _):
            storage.delete(range: offset..<(offset + length))
        }
        return storage.snapshot()
    }

    public var canUndo: Bool { undoManager.canUndo }
    public var canRedo: Bool { undoManager.canRedo }

    // MARK: - Operation Log

    /// The operation log for this session.
    public var operations: [EditOperation] {
        operationLog.operations
    }

    /// Number of recorded operations.
    public var operationCount: Int {
        operationLog.count
    }
}
