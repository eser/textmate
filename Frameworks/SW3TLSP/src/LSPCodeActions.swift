// SW³ TextFellow — LSP Code Actions
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Requests code actions from LSP servers and presents them
// as a native NSMenu contextual menu. Trigger: ⌘. at cursor.

import AppKit

// MARK: - Code Action Types

/// A code action returned by the LSP server.
public struct LSPCodeAction: Sendable {
    public let title: String
    public let kind: String?
    public let isPreferred: Bool
    /// Workspace edit to apply (simplified: just text edits for the current file).
    public let edits: [LSPTextEdit]

    public init(title: String, kind: String? = nil, isPreferred: Bool = false, edits: [LSPTextEdit] = []) {
        self.title = title
        self.kind = kind
        self.isPreferred = isPreferred
        self.edits = edits
    }
}

/// A text edit to apply to a document.
public struct LSPTextEdit: Sendable {
    public let range: LSPRange
    public let newText: String

    public init(range: LSPRange, newText: String) {
        self.range = range
        self.newText = newText
    }
}

// MARK: - Code Action Parsing

/// Parse code actions from LSP JSON response.
public func parseCodeActions(from data: Data) -> [LSPCodeAction] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        return []
    }

    return json.compactMap { dict -> LSPCodeAction? in
        guard let title = dict["title"] as? String else { return nil }
        let kind = dict["kind"] as? String
        let isPreferred = dict["isPreferred"] as? Bool ?? false

        var edits: [LSPTextEdit] = []
        if let edit = dict["edit"] as? [String: Any],
           let changes = edit["changes"] as? [String: [[String: Any]]] {
            for (_, fileEdits) in changes {
                for textEdit in fileEdits {
                    if let rangeDict = textEdit["range"] as? [String: Any],
                       let newText = textEdit["newText"] as? String,
                       let start = rangeDict["start"] as? [String: Any],
                       let end = rangeDict["end"] as? [String: Any],
                       let sl = start["line"] as? Int, let sc = start["character"] as? Int,
                       let el = end["line"] as? Int, let ec = end["character"] as? Int {
                        edits.append(LSPTextEdit(
                            range: LSPRange(
                                start: LSPPosition(line: sl, character: sc),
                                end: LSPPosition(line: el, character: ec)
                            ),
                            newText: newText
                        ))
                    }
                }
            }
        }

        return LSPCodeAction(title: title, kind: kind, isPreferred: isPreferred, edits: edits)
    }
}

// MARK: - Code Action Menu

/// Presents code actions as a native NSMenu at the given screen location.
/// Returns the selected action, or nil if the user dismissed the menu.
@MainActor
public func presentCodeActionMenu(
    actions: [LSPCodeAction],
    at point: NSPoint,
    in view: NSView
) -> LSPCodeAction? {
    guard !actions.isEmpty else { return nil }

    let menu = NSMenu(title: "Code Actions")

    for (index, action) in actions.enumerated() {
        let item = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
        item.tag = index

        // Icon based on action kind
        if let kind = action.kind {
            if kind.hasPrefix("quickfix") {
                item.image = NSImage(systemSymbolName: "wrench", accessibilityDescription: "Quick Fix")
            } else if kind.hasPrefix("refactor") {
                item.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Refactor")
            } else if kind.hasPrefix("source") {
                item.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Source Action")
            }
        }

        if action.isPreferred {
            item.attributedTitle = NSAttributedString(
                string: action.title,
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
            )
        }

        menu.addItem(item)
    }

    // Show menu and get selection
    guard menu.popUp(positioning: nil, at: point, in: view) else {
        return nil
    }

    let selectedTag = menu.highlightedItem?.tag ?? -1
    guard selectedTag >= 0, selectedTag < actions.count else { return nil }
    return actions[selectedTag]
}
