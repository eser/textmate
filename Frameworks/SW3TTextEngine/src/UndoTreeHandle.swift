// SW³ TextFellow — ObjC-compatible UndoTree wrapper
// SPDX-License-Identifier: GPL-3.0-or-later
//
// UndoTree is a generic Swift struct and can't be used from ObjC directly.
// This class wraps UndoTree<String> for the ObjC++ bridge.

import Foundation

@objc(UndoTreeHandle)
public final class UndoTreeHandle: NSObject, @unchecked Sendable {
    private var tree: UndoTree<String>

    @objc public override init() {
        self.tree = UndoTree(initialState: "")
        super.init()
    }

    @objc public func recordState(text: String) {
        tree.record(state: text)
    }

    @objc public func undo() -> String? {
        tree.undo()
        return tree.currentState
    }

    @objc public func redo() -> String? {
        tree.redo()
        return tree.currentState
    }

    @objc public var canUndo: Bool { tree.canUndo }
    @objc public var canRedo: Bool { tree.canRedo }
    @objc public var nodeCount: Int { tree.nodeCount }
    @objc public var currentText: String { tree.currentState }
}
