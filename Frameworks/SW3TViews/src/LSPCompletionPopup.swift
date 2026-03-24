// SW³ TextFellow — LSP Completion Popup
// SPDX-License-Identifier: GPL-3.0-or-later
//
// SwiftUI completion popup triggered by typing or Opt+Tab.
// Shows fuzzy-matched completions with kind icons and detail text.
// Accept: Enter/Tab. Dismiss: Escape. Navigate: ↑/↓.

import AppKit
import SwiftUI

// MARK: - Completion Item Model

@objc(SW3TCompletionItem)
public class CompletionItemModel: NSObject, Identifiable {
    public let id = UUID()
    @objc public let label: String
    @objc public let detail: String?
    @objc public let kind: Int  // LSP CompletionItemKind
    @objc public let insertText: String?

    @objc public init(label: String, detail: String?, kind: Int, insertText: String?) {
        self.label = label
        self.detail = detail
        self.kind = kind
        self.insertText = insertText
    }

    /// SF Symbol name for the completion kind.
    var kindIcon: String {
        switch kind {
        case 1:  return "doc.text"           // Text
        case 2:  return "m.square"           // Method
        case 3:  return "f.square"           // Function
        case 4:  return "hammer"             // Constructor
        case 5:  return "square.stack.3d.up" // Field
        case 6:  return "v.square"           // Variable
        case 7:  return "c.square"           // Class
        case 8:  return "i.square"           // Interface
        case 9:  return "shippingbox"        // Module
        case 10: return "p.square"           // Property
        case 13: return "e.square"           // Enum
        case 14: return "k.square"           // Keyword
        case 15: return "text.snippet"       // Snippet
        case 21: return "cube"               // Struct
        case 22: return "calendar"           // Event
        case 25: return "t.square"           // TypeParameter
        default: return "circle.fill"        // Unknown
        }
    }

    var kindColor: Color {
        switch kind {
        case 2, 3, 4: return .blue       // Methods/Functions
        case 5, 6, 10: return .cyan      // Fields/Variables/Properties
        case 7, 8, 21: return .teal      // Classes/Interfaces/Structs
        case 13:       return .orange    // Enum
        case 14:       return .purple    // Keyword
        case 15:       return .green     // Snippet
        default:       return .secondary // Unknown
        }
    }
}

// MARK: - Completion List View

struct CompletionListView: View {
    let items: [CompletionItemModel]
    @Binding var selectedIndex: Int
    let onAccept: (CompletionItemModel) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Text("No completions")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .padding(12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                CompletionRowView(
                                    item: item,
                                    isSelected: index == selectedIndex
                                )
                                .id(index)
                                .onTapGesture {
                                    onAccept(item)
                                }
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { _, newValue in
                        withAnimation(.none) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 320, height: 240)
        .background(.regularMaterial)
    }
}

struct CompletionRowView: View {
    let item: CompletionItemModel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.kindIcon)
                .font(.system(size: 10))
                .foregroundStyle(item.kindColor)
                .frame(width: 16)

            Text(item.label)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)

            if let detail = item.detail {
                Spacer()
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Completion Panel Controller

@objc(SW3TCompletionController)
public class CompletionController: NSObject, @unchecked Sendable {

    @objc public static let shared = CompletionController()

    private var panel: NSPanel?
    private var items: [CompletionItemModel] = []
    private var selectedIndex = 0
    private var hostingView: NSHostingView<AnyView>?
    private var onAccept: ((CompletionItemModel) -> Void)?

    /// Show completions at a screen position.
    @objc public func show(
        items: [CompletionItemModel],
        at screenPoint: NSPoint,
        in parentWindow: NSWindow,
        onAccept: @escaping (CompletionItemModel) -> Void
    ) {
        self.items = items
        self.selectedIndex = 0
        self.onAccept = onAccept

        dismiss()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = true

        updateView(in: panel)

        // Position below the cursor
        panel.setFrameTopLeftPoint(NSPoint(x: screenPoint.x, y: screenPoint.y - 2))
        parentWindow.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)

        self.panel = panel
    }

    private func updateView(in panel: NSPanel) {
        let binding = Binding<Int>(
            get: { [weak self] in self?.selectedIndex ?? 0 },
            set: { [weak self] in self?.selectedIndex = $0 }
        )
        let accept = onAccept ?? { _ in }
        let view = CompletionListView(items: items, selectedIndex: binding, onAccept: accept)
        let hosting = NSHostingView(rootView: AnyView(view))
        panel.contentView = hosting
        self.hostingView = hosting
    }

    /// Dismiss the completion popup.
    @objc public func dismiss() {
        panel?.parent?.removeChildWindow(panel!)
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    /// Move selection up.
    @objc public func moveUp() {
        guard !items.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
        if let panel { updateView(in: panel) }
    }

    /// Move selection down.
    @objc public func moveDown() {
        guard !items.isEmpty else { return }
        selectedIndex = min(items.count - 1, selectedIndex + 1)
        if let panel { updateView(in: panel) }
    }

    /// Accept the currently selected item.
    @objc public func acceptSelected() {
        guard selectedIndex < items.count else { return }
        onAccept?(items[selectedIndex])
        dismiss()
    }

    /// Whether the popup is currently visible.
    @objc public var isVisible: Bool { panel?.isVisible ?? false }
}
