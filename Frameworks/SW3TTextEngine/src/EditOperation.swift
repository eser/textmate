// SW³ TextFellow — Edit Operations & Batching
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A single text mutation — insert or delete.
public enum EditOperation: Sendable, Equatable {
    case insert(offset: Int, text: String)
    case delete(offset: Int, length: Int)
}

/// A batch of edit operations applied atomically.
/// One actor call, one snapshot, one undo entry.
public struct EditBatch: Sendable {
    public var operations: [EditOperation] = []

    public init() {}

    public mutating func insert(_ text: String, at offset: Int) {
        operations.append(.insert(offset: offset, text: text))
    }

    public mutating func delete(at offset: Int, length: Int) {
        operations.append(.delete(offset: offset, length: length))
    }

    public var isEmpty: Bool { operations.isEmpty }
}

/// Applies an EditBatch to a TextStorage, adjusting offsets as operations
/// are applied (later operations account for earlier ones shifting content).
public func apply<S: TextStorage>(batch: EditBatch, to storage: inout S) where S.Index == Int {
    // Sort operations by offset descending so each operation doesn't
    // invalidate subsequent offsets
    let sorted = batch.operations.sorted {
        switch ($0, $1) {
        case (.insert(let a, _), .insert(let b, _)): return a > b
        case (.delete(let a, _), .delete(let b, _)): return a > b
        case (.insert(let a, _), .delete(let b, _)): return a > b
        case (.delete(let a, _), .insert(let b, _)): return a > b
        }
    }

    for op in sorted {
        switch op {
        case .insert(let offset, let text):
            storage.insert(text, at: offset)
        case .delete(let offset, let length):
            storage.delete(range: offset..<(offset + length))
        }
    }
}
