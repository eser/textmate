// SW³ TextFellow — Undo Tree Protocol
// SPDX-License-Identifier: GPL-3.0-or-later

/// Protocol for undo/redo management.
///
/// Designed for tree-based undo from day one. Phase 1 ships with a
/// linear implementation; Phase 2 upgrades to full persistent undo tree
/// with branching, cross-session persistence, and visual navigation.
///
/// ```
///  Undo Tree (Phase 2):
///
///       [initial]
///           │
///       [edit A]
///        ╱      ╲
///   [edit B]  [edit C]  ← branching: undoing B and typing C
///       │         │        creates a new branch
///   [edit D]  [edit E]
/// ```
public protocol UndoTree: Sendable {
    /// Record an edit operation with its associated snapshot.
    func record(operation: EditOperation, snapshot: TextStorageSnapshot)

    /// Undo the most recent operation, returning the previous snapshot.
    /// Returns nil if at the root (nothing to undo).
    func undo() -> TextStorageSnapshot?

    /// Redo the most recently undone operation.
    /// Returns nil if at the tip (nothing to redo).
    func redo() -> TextStorageSnapshot?

    /// Whether undo is available.
    var canUndo: Bool { get }

    /// Whether redo is available.
    var canRedo: Bool { get }
}

/// Linear undo implementation for Phase 1.
///
/// Simple undo/redo stack. Will be replaced by a tree implementation
/// in Phase 2, but conforms to the same protocol so all callers
/// are unaffected by the upgrade.
public final class LinearUndoManager: UndoTree, @unchecked Sendable {
    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    private let lock = LockedValue<Void>(())

    public init() {}

    public func record(operation: EditOperation, snapshot: TextStorageSnapshot) {
        lock.withLock { _ in
            undoStack.append(UndoEntry(operation: operation, snapshot: snapshot))
            redoStack.removeAll()
        }
    }

    public func undo() -> TextStorageSnapshot? {
        lock.withLock { _ in
            guard let entry = undoStack.popLast() else { return nil }
            redoStack.append(entry)
            return entry.snapshot // snapshot = state BEFORE this edit was applied
        }
    }

    /// Pop the most recent redo entry. Returns the operation to re-apply.
    public func redo() -> TextStorageSnapshot? {
        // Note: we return nil here because redo needs to re-apply the
        // operation. The caller (TextEditSession) handles re-application.
        // This method just moves the entry back to the undo stack.
        lock.withLock { _ in
            guard let entry = redoStack.popLast() else { return nil }
            undoStack.append(entry)
            // Not used — caller re-applies operation
            return TextStorageSnapshot(text: "", lineCount: 0)
        }
    }

    /// Get the operation from the most recent redo entry without popping.
    public func peekRedo() -> EditOperation? {
        lock.withLock { _ in redoStack.last?.operation }
    }

    public var canUndo: Bool {
        lock.withLock { _ in !undoStack.isEmpty }
    }

    public var canRedo: Bool {
        lock.withLock { _ in !redoStack.isEmpty }
    }
}

struct UndoEntry: Sendable {
    let operation: EditOperation
    let snapshot: TextStorageSnapshot
}
