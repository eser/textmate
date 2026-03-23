// SW³ TextFellow — Tree-sitter Highlighter
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
// tree-sitter C API is available via the bridging header

/// SyntaxHighlighter backed by tree-sitter incremental parsing.
///
/// Pipeline: source text → TSParser → TSTree → walk nodes → [HighlightToken]
///
/// This runs alongside the existing TextMate grammar engine.
/// Tree-sitter is used when a grammar is available; TextMate grammars
/// are the fallback for languages without a tree-sitter grammar.
public final class TreeSitterHighlighter: SyntaxHighlighter, @unchecked Sendable {
    public let language: String

    private let parser: OpaquePointer  // TSParser*
    private var tree: OpaquePointer?   // TSTree*
    private var isDirty: Bool = true

    /// Create a highlighter for the given language.
    /// - Parameter language: language identifier (e.g., "swift")
    /// - Parameter tsLanguage: the tree-sitter language pointer from a grammar package
    public init?(language: String, tsLanguage: OpaquePointer) {
        self.language = language
        guard let p = ts_parser_new() else { return nil }
        self.parser = p

        if !ts_parser_set_language(parser, tsLanguage) {
            ts_parser_delete(parser)
            return nil
        }
    }

    deinit {
        if let tree { ts_tree_delete(tree) }
        ts_parser_delete(parser)
    }

    // MARK: - SyntaxHighlighter

    public func highlight(in range: Range<Int>, source: String) -> [HighlightToken] {
        if isDirty {
            reparse(source: source)
        }

        guard let tree else { return [] }

        var tokens: [HighlightToken] = []
        let rootNode = ts_tree_root_node(tree)
        collectTokens(node: rootNode, in: range, tokens: &tokens)
        return tokens
    }

    public func didEdit(at range: Range<Int>, delta: Int) {
        isDirty = true

        // Inform tree-sitter about the edit for incremental re-parse
        if let tree {
            var edit = TSInputEdit(
                start_byte: UInt32(range.lowerBound),
                old_end_byte: UInt32(range.upperBound),
                new_end_byte: UInt32(range.lowerBound + max(0, range.count + delta)),
                start_point: TSPoint(row: 0, column: 0),
                old_end_point: TSPoint(row: 0, column: 0),
                new_end_point: TSPoint(row: 0, column: 0)
            )
            ts_tree_edit(tree, &edit)
        }
    }

    // MARK: - Private

    private func reparse(source: String) {
        let newTree = source.withCString { cstr in
            ts_parser_parse_string(parser, tree, cstr, UInt32(strlen(cstr)))
        }

        if let oldTree = tree {
            ts_tree_delete(oldTree)
        }

        tree = newTree
        isDirty = false
    }

    /// Walk the tree and collect tokens that intersect the requested range.
    private func collectTokens(node: TSNode, in range: Range<Int>, tokens: inout [HighlightToken]) {
        let startByte = Int(ts_node_start_byte(node))
        let endByte = Int(ts_node_end_byte(node))

        // Skip nodes outside the requested range
        guard startByte < range.upperBound && endByte > range.lowerBound else { return }

        let childCount = ts_node_child_count(node)
        if childCount == 0 {
            // Leaf node — produce a token if it has a meaningful type
            if let nodeType = ts_node_type(node), !ts_node_is_extra(node) {
                let scope = String(cString: nodeType)
                if scope != "end" && !scope.isEmpty {
                    let tokenRange = max(startByte, range.lowerBound)..<min(endByte, range.upperBound)
                    if !tokenRange.isEmpty {
                        tokens.append(HighlightToken(range: tokenRange, scope: scope))
                    }
                }
            }
        } else {
            // Recurse into children
            for i in 0..<childCount {
                let child = ts_node_child(node, i)
                collectTokens(node: child, in: range, tokens: &tokens)
            }
        }
    }
}
