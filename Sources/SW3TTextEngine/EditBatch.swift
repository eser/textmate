// SW³ TextFellow — Edit Batch
// SPDX-License-Identifier: GPL-3.0-or-later

/// A batch of edit operations to be applied atomically.
///
/// Instead of calling `insert()` N times for N cursors (N async
/// round-trips to TextEngineActor), the caller assembles an EditBatch
/// and sends it as a single `apply(batch:)` call. The actor processes
/// the entire batch atomically, produces one snapshot, and the undo
/// system records it as a single undoable unit.
///
/// ```
///  Multi-cursor typing "x" at 3 positions:
///
///  Without batching:          With batching:
///  ┌──────────────┐           ┌──────────────┐
///  │ await insert │ ×3        │ await apply  │ ×1
///  │ (3 actor     │           │ (1 actor     │
///  │  round-trips)│           │  round-trip) │
///  └──────────────┘           └──────────────┘
///  3 snapshots, 3 undo        1 snapshot, 1 undo
///  entries, 3 notifications   entry, 1 notification
/// ```
///
/// **Critical for performance:** 50 simultaneous cursors inserting
/// a character on a 100K-line file must complete within one frame
/// (8ms at 120fps).
public struct EditBatch: Sendable {
    /// The individual operations in this batch.
    /// Applied in order. Offsets are relative to the document state
    /// at the START of the batch — the caller is responsible for
    /// adjusting offsets if operations overlap.
    public var operations: [BatchOperation]

    public init(_ operations: [BatchOperation] = []) {
        self.operations = operations
    }

    /// Add an insertion to the batch.
    public mutating func insert(_ text: String, at offset: Int) {
        operations.append(.insert(offset: offset, text: text))
    }

    /// Add a deletion to the batch.
    public mutating func delete(range: Range<Int>) {
        operations.append(.delete(range: range))
    }

    /// Number of operations in the batch.
    public var count: Int { operations.count }

    /// Whether the batch is empty.
    public var isEmpty: Bool { operations.isEmpty }
}

/// A single operation within a batch (no timestamp — assigned during apply).
public enum BatchOperation: Sendable {
    case insert(offset: Int, text: String)
    case delete(range: Range<Int>)
}
