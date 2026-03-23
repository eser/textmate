// SW³ TextFellow — Edit Operations
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A single atomic edit operation — either an insertion or a deletion.
///
/// Every mutation to TextStorage is recorded as an EditOperation with a
/// logical timestamp. This operation log is the foundation for:
/// - Undo/redo (replay or reverse operations)
/// - Crash recovery (replay from swap file)
/// - Future CRDT readiness (operations can be merged/rebased)
public enum EditOperation: Sendable, Codable, Equatable {
    /// Text was inserted at the given offset.
    case insert(offset: Int, text: String, timestamp: UInt64)

    /// Text was deleted from the given range.
    case delete(offset: Int, length: Int, deletedText: String, timestamp: UInt64)

    /// The logical timestamp of this operation.
    public var timestamp: UInt64 {
        switch self {
        case .insert(_, _, let ts): return ts
        case .delete(_, _, _, let ts): return ts
        }
    }

    /// Produce the inverse operation (for undo).
    public var inverse: EditOperation {
        switch self {
        case .insert(let offset, let text, let ts):
            return .delete(offset: offset, length: text.utf8.count, deletedText: text, timestamp: ts)
        case .delete(let offset, _, let deletedText, let ts):
            return .insert(offset: offset, text: deletedText, timestamp: ts)
        }
    }
}

/// Ordered log of all edit operations, with monotonic timestamps.
///
/// ```
///  Time ──────────────────────────────────────────►
///  [insert@0] [insert@5] [delete@3..7] [insert@3]
///       t=1        t=2          t=3          t=4
/// ```
public final class OperationLog: Sendable {
    private let _operations: LockedValue<[EditOperation]>
    private let _nextTimestamp: LockedValue<UInt64>

    public init() {
        self._operations = LockedValue([])
        self._nextTimestamp = LockedValue(1)
    }

    /// Record an operation and return its assigned timestamp.
    @discardableResult
    public func record(_ operation: EditOperation) -> UInt64 {
        _operations.withLock { $0.append(operation) }
        return operation.timestamp
    }

    /// Generate the next monotonic timestamp.
    public func nextTimestamp() -> UInt64 {
        _nextTimestamp.withLock { ts in
            let current = ts
            ts += 1
            return current
        }
    }

    /// All recorded operations, in order.
    public var operations: [EditOperation] {
        _operations.withLock { $0 }
    }

    /// Number of recorded operations.
    public var count: Int {
        _operations.withLock { $0.count }
    }
}

/// Thread-safe value wrapper using os_unfair_lock semantics via Swift's approach.
final class LockedValue<Value: Sendable>: @unchecked Sendable {
    private var _value: Value
    private let _lock = NSLock()

    init(_ value: Value) {
        self._value = value
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        _lock.lock()
        defer { _lock.unlock() }
        return body(&_value)
    }
}
