import Foundation

// MARK: - Node ID

/// Opaque, unique identifier for a node in the undo tree.
public struct UndoNodeID: Hashable, Sendable, CustomStringConvertible {
    private let rawValue: UInt64

    fileprivate init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public var description: String { "node-\(rawValue)" }
}

// MARK: - Undo Node

/// A single node in the branching undo tree.
/// Each node captures a snapshot of the document state along with
/// metadata for tree traversal and UI visualization.
public struct UndoNode<State: Sendable>: Sendable {
    /// Unique identifier for this node.
    public let id: UndoNodeID
    /// The captured document state at this point.
    public let state: State
    /// ID of the parent node, or `nil` for the root.
    public let parentID: UndoNodeID?
    /// IDs of child nodes (branches).
    public internal(set) var childIDs: [UndoNodeID]
    /// When this node was created.
    public let timestamp: Date
    /// Optional label for display in a branch picker UI.
    public var label: String?

    internal init(id: UndoNodeID, state: State, parentID: UndoNodeID?,
                  timestamp: Date = Date(), label: String? = nil) {
        self.id = id
        self.state = state
        self.parentID = parentID
        self.childIDs = []
        self.timestamp = timestamp
        self.label = label
    }
}

// MARK: - Branch Info

/// Summary of a branch in the undo tree, for UI visualization.
public struct BranchInfo<State: Sendable>: Sendable {
    /// The node IDs along this branch from root to leaf.
    public let path: [UndoNodeID]
    /// The leaf node's state.
    public let leafState: State
    /// The leaf node's timestamp.
    public let leafTimestamp: Date
}

// MARK: - Undo Tree

/// A branching undo tree that preserves the full edit history.
///
/// Unlike a linear undo stack, `UndoTree` never discards states when the user
/// undoes and then makes a new edit. Instead, a new branch is created from the
/// current node, preserving all previous branches for later recovery.
///
/// ## Usage
///
/// ```swift
/// var tree = UndoTree(initialState: "Hello")
/// tree.record(state: "Hello, World")
/// tree.record(state: "Hello, World!")
/// tree.undo()                          // back to "Hello, World"
/// tree.record(state: "Hello, Swift")   // creates a new branch
/// tree.undo()                          // back to "Hello, World"
/// tree.redo(branchIndex: 0)            // goes to "Hello, World!"
/// ```
public struct UndoTree<State: Sendable>: Sendable {

    // MARK: Storage

    /// All nodes indexed by ID for O(1) access.
    private var nodes: [UndoNodeID: UndoNode<State>] = [:]

    /// The ID of the currently active node.
    private var currentID: UndoNodeID

    /// The root node's ID.
    public let rootID: UndoNodeID

    /// Monotonically increasing counter for generating unique node IDs.
    private var nextID: UInt64 = 1

    // MARK: Init

    /// Create an undo tree with an initial state as the root node.
    public init(initialState: State) {
        let rootNodeID = UndoNodeID(0)
        let root = UndoNode(id: rootNodeID, state: initialState, parentID: nil)
        self.nodes = [rootNodeID: root]
        self.currentID = rootNodeID
        self.rootID = rootNodeID
    }

    // MARK: Current State

    /// The state at the currently active node.
    public var currentState: State {
        nodes[currentID]!.state
    }

    /// The ID of the currently active node.
    public var currentNodeID: UndoNodeID { currentID }

    /// The node at the current position.
    public var currentNode: UndoNode<State> { nodes[currentID]! }

    /// Total number of nodes in the tree.
    public var nodeCount: Int { nodes.count }

    // MARK: Record

    /// Record a new state, creating a child branch from the current node.
    ///
    /// - Parameters:
    ///   - state: The new document state to record.
    ///   - label: Optional label for display in a branch picker.
    /// - Returns: The ID of the newly created node.
    @discardableResult
    public mutating func record(state: State, label: String? = nil) -> UndoNodeID {
        let newID = UndoNodeID(nextID)
        nextID += 1

        let newNode = UndoNode(id: newID, state: state, parentID: currentID, label: label)
        nodes[newID] = newNode
        nodes[currentID]!.childIDs.append(newID)
        currentID = newID
        return newID
    }

    // MARK: Undo

    /// Move to the parent node (undo).
    ///
    /// - Returns: `true` if undo succeeded, `false` if already at root.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let parentID = nodes[currentID]?.parentID else { return false }
        currentID = parentID
        return true
    }

    /// Undo multiple steps, stopping at the root if reached.
    ///
    /// - Parameter steps: Number of undo steps.
    /// - Returns: The actual number of steps undone.
    @discardableResult
    public mutating func undo(steps: Int) -> Int {
        var undone = 0
        for _ in 0..<steps {
            guard undo() else { break }
            undone += 1
        }
        return undone
    }

    // MARK: Redo

    /// Move to a child node (redo).
    ///
    /// - Parameter branchIndex: Which child branch to follow. Defaults to the last
    ///   child (most recently created branch). Use `0` for the oldest branch.
    /// - Returns: `true` if redo succeeded, `false` if no children exist.
    @discardableResult
    public mutating func redo(branchIndex: Int? = nil) -> Bool {
        let children = nodes[currentID]!.childIDs
        guard !children.isEmpty else { return false }

        let index: Int
        if let branchIndex, branchIndex >= 0, branchIndex < children.count {
            index = branchIndex
        } else {
            // Default: follow the most recently created branch (last child).
            index = children.count - 1
        }

        currentID = children[index]
        return true
    }

    // MARK: Jump

    /// Jump directly to any node in the tree by its ID.
    ///
    /// - Parameter nodeId: The target node ID.
    /// - Returns: `true` if the node exists and the jump succeeded.
    @discardableResult
    public mutating func jumpTo(nodeId: UndoNodeID) -> Bool {
        guard nodes[nodeId] != nil else { return false }
        currentID = nodeId
        return true
    }

    // MARK: Node Access

    /// Retrieve a node by its ID.
    public func node(for id: UndoNodeID) -> UndoNode<State>? {
        nodes[id]
    }

    /// Get all direct children of the current node.
    public var currentChildren: [UndoNode<State>] {
        nodes[currentID]!.childIDs.compactMap { nodes[$0] }
    }

    /// Check whether undo is possible from the current position.
    public var canUndo: Bool {
        nodes[currentID]?.parentID != nil
    }

    /// Check whether redo is possible from the current position.
    public var canRedo: Bool {
        let children = nodes[currentID]?.childIDs ?? []
        return !children.isEmpty
    }

    /// Number of branches (children) at the current node.
    public var branchCount: Int {
        nodes[currentID]?.childIDs.count ?? 0
    }

    // MARK: Path

    /// Return the path from root to the current node as an array of node IDs.
    public var pathFromRoot: [UndoNodeID] {
        var path: [UndoNodeID] = []
        var cursor: UndoNodeID? = currentID
        while let id = cursor {
            path.append(id)
            cursor = nodes[id]?.parentID
        }
        return path.reversed()
    }

    /// Return the path from root to a specific node.
    public func pathFromRoot(to nodeId: UndoNodeID) -> [UndoNodeID]? {
        guard nodes[nodeId] != nil else { return nil }
        var path: [UndoNodeID] = []
        var cursor: UndoNodeID? = nodeId
        while let id = cursor {
            path.append(id)
            cursor = nodes[id]?.parentID
        }
        return path.reversed()
    }

    // MARK: Branch Enumeration

    /// Enumerate all branches (root-to-leaf paths) in the tree.
    /// Useful for building a branch picker UI.
    public func allBranches() -> [BranchInfo<State>] {
        var result: [BranchInfo<State>] = []
        var currentPath: [UndoNodeID] = []

        func dfs(_ nodeID: UndoNodeID) {
            currentPath.append(nodeID)
            let node = nodes[nodeID]!

            if node.childIDs.isEmpty {
                // Leaf node — record this branch.
                result.append(BranchInfo(
                    path: currentPath,
                    leafState: node.state,
                    leafTimestamp: node.timestamp
                ))
            } else {
                for childID in node.childIDs {
                    dfs(childID)
                }
            }

            currentPath.removeLast()
        }

        dfs(rootID)
        return result
    }

    // MARK: Tree Visualization

    /// Build a textual representation of the tree for debugging.
    /// The current node is marked with `*`.
    public func debugDescription(describeState: (State) -> String) -> String {
        var lines: [String] = []

        func walk(_ nodeID: UndoNodeID, indent: String, isLast: Bool) {
            let node = nodes[nodeID]!
            let marker = nodeID == currentID ? "*" : " "
            let connector = isLast ? "└── " : "├── "
            let stateDesc = describeState(node.state)
            let label = node.label.map { " [\($0)]" } ?? ""
            lines.append("\(indent)\(connector)\(marker)\(node.id): \(stateDesc)\(label)")

            let childIndent = indent + (isLast ? "    " : "│   ")
            for (i, childID) in node.childIDs.enumerated() {
                walk(childID, indent: childIndent, isLast: i == node.childIDs.count - 1)
            }
        }

        let root = nodes[rootID]!
        let rootMarker = rootID == currentID ? "*" : " "
        lines.append("\(rootMarker)\(root.id): \(describeState(root.state))")
        for (i, childID) in root.childIDs.enumerated() {
            walk(childID, indent: "", isLast: i == root.childIDs.count - 1)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: Pruning

    /// Remove a subtree rooted at the given node, including all descendants.
    /// Cannot remove the root or the current node (or any ancestor of the current node).
    ///
    /// - Returns: The number of nodes removed, or 0 if the operation was rejected.
    @discardableResult
    public mutating func prune(subtreeAt nodeId: UndoNodeID) -> Int {
        // Prevent removing root.
        guard nodeId != rootID else { return 0 }

        // Prevent removing the current node or any of its ancestors.
        let currentAncestors = Set(pathFromRoot)
        guard !currentAncestors.contains(nodeId) else { return 0 }

        // Collect all nodes in the subtree.
        var toRemove: [UndoNodeID] = []
        var queue: [UndoNodeID] = [nodeId]
        while !queue.isEmpty {
            let id = queue.removeFirst()
            toRemove.append(id)
            if let node = nodes[id] {
                queue.append(contentsOf: node.childIDs)
            }
        }

        // Remove from parent's child list.
        if let parentID = nodes[nodeId]?.parentID {
            nodes[parentID]?.childIDs.removeAll { $0 == nodeId }
        }

        // Remove all subtree nodes.
        for id in toRemove {
            nodes.removeValue(forKey: id)
        }

        return toRemove.count
    }
}
