// SW³ TextFellow — Split Editor View
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Split panes — ⌘\ vertical, ⌘⌥\ horizontal.
//
// Linked splits: same file in two panes shares TextStorage,
// undo tree, and syntax state. Edits sync instantly.
// Scroll positions are independent.
//
// Default state: single pane, no split UI visible (progressive disclosure).
//
// iPad: max 2 panes.

import SwiftUI

/// Split orientation.
public enum SplitOrientation: Sendable {
    case none       // Single pane (default)
    case vertical   // Side by side (⌘\)
    case horizontal // Top and bottom (⌘⌥\)
}

/// Container that manages split panes.
///
/// When split is active, both panes share the same EditorState
/// (linked editing) but maintain independent scroll positions.
public struct SplitEditorView<Content: View>: View {
    @Binding var orientation: SplitOrientation
    let content: () -> Content

    public init(
        orientation: Binding<SplitOrientation>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._orientation = orientation
        self.content = content
    }

    public var body: some View {
        switch orientation {
        case .none:
            content()

        case .vertical:
            HSplitView {
                content()
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                content()
            }

        case .horizontal:
            VSplitView {
                content()
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
                content()
            }
        }
    }
}
