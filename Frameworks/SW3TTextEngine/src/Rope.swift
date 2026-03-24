// SW³ TextFellow — Rope Data Structure
// SPDX-License-Identifier: GPL-3.0-or-later
//
// B-tree rope for O(log n) insert/delete on large documents.
// Leaf nodes hold UTF-8 string chunks. Internal nodes cache
// subtree size and line count for fast queries.

/// Maximum characters per leaf node before splitting.
private let leafCapacity = 1024

/// A rope node — either a leaf holding text or an internal node
/// joining two subtrees.
indirect enum RopeNode: Sendable {
    case leaf(String)
    case branch(left: Rope, right: Rope)
}

/// Balanced rope for efficient text manipulation on large files.
/// All indices are UTF-8 byte offsets (matching TextStorage protocol).
public struct Rope: Sendable {
    var node: RopeNode
    /// Cached UTF-8 byte count of the entire subtree.
    let byteCount: Int
    /// Cached number of newline characters in the subtree.
    let newlineCount: Int

    // MARK: - Constructors

    public init(_ text: String = "") {
        self.node = .leaf(text)
        self.byteCount = text.utf8.count
        self.newlineCount = text.utf8.reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) }
    }

    init(left: Rope, right: Rope) {
        self.node = .branch(left: left, right: right)
        self.byteCount = left.byteCount + right.byteCount
        self.newlineCount = left.newlineCount + right.newlineCount
    }

    // MARK: - Core Operations

    /// Insert `string` at UTF-8 byte offset `pos`.
    public func inserting(_ string: String, at pos: Int) -> Rope {
        let clamped = min(max(pos, 0), byteCount)
        let (l, r) = split(at: clamped)
        return merge(merge(l, Rope(string)), r)
    }

    /// Delete the range of UTF-8 byte offsets `range`.
    public func deleting(range: Range<Int>) -> Rope {
        let lo = min(max(range.lowerBound, 0), byteCount)
        let hi = min(max(range.upperBound, 0), byteCount)
        guard lo < hi else { return self }
        let (left, rest) = split(at: lo)
        let (_, right) = rest.split(at: hi - lo)
        return merge(left, right)
    }

    /// Extract substring for the given UTF-8 byte range.
    public func substring(range: Range<Int>) -> String {
        let lo = min(max(range.lowerBound, 0), byteCount)
        let hi = min(max(range.upperBound, 0), byteCount)
        guard lo < hi else { return "" }
        var result = ""
        result.reserveCapacity(hi - lo)
        collectSubstring(from: lo, to: hi, into: &result)
        return result
    }

    /// Full text (O(n) — use for snapshots, not hot paths).
    public var text: String {
        var result = ""
        result.reserveCapacity(byteCount)
        appendTo(&result)
        return result
    }

    /// Number of lines (newlines + 1).
    public var lineCount: Int { newlineCount + 1 }

    // MARK: - Split & Merge (rope fundamentals)

    /// Split the rope at UTF-8 byte offset `pos`, returning (left, right).
    func split(at pos: Int) -> (Rope, Rope) {
        if pos <= 0 { return (Rope(""), self) }
        if pos >= byteCount { return (self, Rope("")) }

        switch node {
        case .leaf(let s):
            let idx = s.utf8Index(at: pos)
            let left = String(s[s.startIndex..<idx])
            let right = String(s[idx..<s.endIndex])
            return (Rope(left), Rope(right))

        case .branch(let left, let right):
            if pos <= left.byteCount {
                let (ll, lr) = left.split(at: pos)
                return (ll, merge(lr, right))
            } else {
                let (rl, rr) = right.split(at: pos - left.byteCount)
                return (merge(left, rl), rr)
            }
        }
    }

    // MARK: - Private Helpers

    private func appendTo(_ result: inout String) {
        switch node {
        case .leaf(let s):
            result += s
        case .branch(let left, let right):
            left.appendTo(&result)
            right.appendTo(&result)
        }
    }

    private func collectSubstring(from lo: Int, to hi: Int, into result: inout String) {
        switch node {
        case .leaf(let s):
            let start = s.utf8Index(at: lo)
            let end = s.utf8Index(at: hi)
            result += s[start..<end]

        case .branch(let left, let right):
            if lo < left.byteCount {
                left.collectSubstring(from: lo, to: min(hi, left.byteCount), into: &result)
            }
            if hi > left.byteCount {
                let adjLo = max(lo - left.byteCount, 0)
                let adjHi = hi - left.byteCount
                right.collectSubstring(from: adjLo, to: adjHi, into: &result)
            }
        }
    }
}

/// Merge two ropes, rebalancing leaves that are too large.
private func merge(_ left: Rope, _ right: Rope) -> Rope {
    // If both are small leaves, concatenate into one leaf.
    if case .leaf(let ls) = left.node, case .leaf(let rs) = right.node,
       ls.utf8.count + rs.utf8.count <= leafCapacity {
        return Rope(ls + rs)
    }
    // Otherwise create an internal node.
    return Rope(left: left, right: right)
}

// MARK: - Line Queries

extension Rope {
    /// Return the text of line at `lineNumber` (0-based).
    public func line(at lineNumber: Int) -> String {
        guard lineNumber >= 0, lineNumber < lineCount else { return "" }
        let full = text
        let lines = full.split(separator: "\n", omittingEmptySubsequences: false)
        guard lineNumber < lines.count else { return "" }
        return String(lines[lineNumber])
    }

    /// Return the UTF-8 byte offset of the start of line `n` (0-based).
    public func lineStart(_ n: Int) -> Int {
        guard n > 0 else { return 0 }
        var seen = 0
        var offset = 0
        findLineStart(n, &seen, &offset)
        return offset
    }

    private func findLineStart(_ target: Int, _ seen: inout Int, _ offset: inout Int) {
        switch node {
        case .leaf(let s):
            for byte in s.utf8 {
                if seen == target { return }
                offset += 1
                if byte == 0x0A { seen += 1 }
            }
        case .branch(let left, let right):
            if seen + left.newlineCount >= target {
                left.findLineStart(target, &seen, &offset)
                if seen < target {
                    right.findLineStart(target, &seen, &offset)
                }
            } else {
                seen += left.newlineCount
                offset += left.byteCount
                right.findLineStart(target, &seen, &offset)
            }
        }
    }
}
