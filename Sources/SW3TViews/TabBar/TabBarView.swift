// SW³ TextFellow — Tab Bar View
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Faithful reproduction of TextMate's OakTabBarView with animations:
// - Minimal, flat design matching TextMate exactly
// - Selected tab: transparent background (alpha=0)
// - Unselected tab: 10% text color overlay
// - Hover: 20% text color overlay
// - 1px dividers at 25% black
// - Close button (16x16) on left, appears on hover/selection
// - Tab icon (16x16) + title
//
// Animations (TextMate-style, all <200ms):
// - New tabs slide in from right
// - Closed tabs collapse to zero width
// - Preview tab replacement crossfades
// - Selection change has subtle background transition

import SwiftUI
import SW3TTextEngine

/// A single tab's data model.
public struct TabItem: Identifiable, Equatable {
    public let id: ULID
    public var title: String
    public var icon: String
    public var isModified: Bool
    public var isPreview: Bool
    public var isPinned: Bool

    public init(
        id: ULID = ULID(),
        title: String,
        icon: String = "doc.text",
        isModified: Bool = false,
        isPreview: Bool = false,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isModified = isModified
        self.isPreview = isPreview
        self.isPinned = isPinned
    }
}

/// TextMate-faithful tab bar with smooth animations.
public struct TabBarView: View {
    @Binding var tabs: [TabItem]
    @Binding var selectedTabID: ULID?
    var onClose: ((ULID) -> Void)?

    @State private var hoveredTabID: ULID?

    public init(
        tabs: Binding<[TabItem]>,
        selectedTabID: Binding<ULID?>,
        onClose: ((ULID) -> Void)? = nil
    ) {
        self._tabs = tabs
        self._selectedTabID = selectedTabID
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Pinned tabs — icon-only, anchored left
            ForEach(tabs.filter(\.isPinned)) { tab in
                pinnedTabView(for: tab)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                divider()
            }

            // Regular tabs — with slide/collapse animations
            ForEach(tabs.filter { !$0.isPinned }) { tab in
                tabView(for: tab)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity)
                    ))
                if tab.id != tabs.filter({ !$0.isPinned }).last?.id {
                    divider()
                }
            }
            Spacer()
        }
        .animation(.spring(duration: 0.15), value: tabs.map(\.id))
        .animation(.easeInOut(duration: 0.1), value: selectedTabID)
        .frame(height: 24)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// 1px divider (TextMate: black at 25% alpha).
    @ViewBuilder
    private func divider() -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
    }

    /// Pinned tab — icon only, compact.
    @ViewBuilder
    private func pinnedTabView(for tab: TabItem) -> some View {
        let isSelected = tab.id == selectedTabID

        Image(systemName: tab.icon)
            .font(.system(size: 12))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(width: 28, height: 24)
            .background(tabBackgroundColor(isSelected: isSelected, isHovered: false))
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.1)) { selectedTabID = tab.id }
            }
    }

    @ViewBuilder
    private func tabView(for tab: TabItem) -> some View {
        let isSelected = tab.id == selectedTabID
        let isHovered = tab.id == hoveredTabID

        HStack(spacing: 0) {
            // Close button — 16x16, fades in on hover (TextMate style)
            Button(action: {
                withAnimation(.spring(duration: 0.15)) { onClose?(tab.id) }
            }) {
                Image(systemName: tab.isModified ? "circle.fill" : "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .padding(.leading, 3)
            .opacity(isHovered || isSelected ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.1), value: isHovered)

            // Tab icon — 16x16
            Image(systemName: tab.icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .padding(.leading, 4)

            // Title — italic for preview tabs
            Text(tab.title)
                .font(.system(size: 11))
                .italic(tab.isPreview)
                .foregroundStyle(.secondary)
                .opacity(isSelected ? 1.0 : 0.5)
                .lineLimit(1)
                .padding(.leading, 4)
                .padding(.trailing, 6)
                .contentTransition(.opacity) // Smooth crossfade on title change
        }
        .frame(height: 24)
        .background(tabBackgroundColor(isSelected: isSelected, isHovered: isHovered))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) { selectedTabID = tab.id }
        }
        .onTapGesture(count: 2) {
            if let idx = tabs.firstIndex(where: { $0.id == tab.id }), tabs[idx].isPreview {
                withAnimation(.easeInOut(duration: 0.15)) { tabs[idx].isPreview = false }
            }
        }
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : nil
        }
    }

    /// Tab background color — TextMate's exact opacity values.
    private func tabBackgroundColor(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected {
            return Color.primary.opacity(0.0)
        } else if isHovered {
            return Color.primary.opacity(0.2)
        } else {
            return Color.primary.opacity(0.1)
        }
    }
}

#if DEBUG
#Preview("Tab Bar — Animated") {
    @Previewable @State var tabs = [
        TabItem(title: "main.swift", icon: "swift"),
        TabItem(title: "Package.swift", icon: "doc.text", isModified: true),
        TabItem(title: "README.md", icon: "doc.text"),
    ]
    @Previewable @State var selected: ULID? = nil

    VStack(spacing: 0) {
        TabBarView(tabs: $tabs, selectedTabID: $selected) { id in
            tabs.removeAll { $0.id == id }
        }
        .onAppear { selected = tabs.first?.id }

        Color(nsColor: .textBackgroundColor)
            .frame(height: 300)

        HStack {
            Button("Add Tab") {
                let tab = TabItem(title: "new-\(tabs.count).swift")
                tabs.append(tab)
                selected = tab.id
            }
            Button("Add Preview") {
                let tab = TabItem(title: "preview.txt", isPreview: true)
                tabs.append(tab)
                selected = tab.id
            }
        }
        .padding()
    }
    .frame(width: 600)
}
#endif
