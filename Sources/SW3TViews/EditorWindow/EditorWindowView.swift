// SW³ TextFellow — Main Editor Window
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Stock TextMate default state (what the user sees):
//
//  ┌──────────────────────────────────────┐
//  │         untitled                     │  ← standard title bar, filename centered
//  ├───┬──────────────────────────────────┤
//  │ 1 │                                 │  ← gutter (narrow) + editor area
//  │   │                                 │
//  │   │                                 │
//  │   │                                 │
//  │   │                                 │
//  ├───┴──────────────────────────────────┤
//  │ Line:  1 │ Plain Text ◇ │ Tab Size… │  ← status bar
//  └──────────────────────────────────────┘
//
//  NOTHING ELSE. No sidebar. No toolbar. No tab bar (single file).
//  No command palette. No panels. Clean canvas.

import SwiftUI
import SW3TDocument
import SW3TTextEngine
import SW3TSyntax
import SW3TViewport
import SW3TRenderer
import Metal

public struct EditorWindowView: View {
    @State private var project = ProjectModel()
    @State private var tabs: [TabItem] = [TabItem(title: "untitled")]
    @State private var selectedTabID: ULID?
    @State private var fileSelection: Set<ULID> = []
    @State private var statusBarState = StatusBarState()
    @State private var editorState = EditorState(text: "")
    @State private var languageRegistry = LanguageRegistry()

    // Progressive disclosure — ALL hidden by default
    @State private var showSidebar = false
    @State private var showCommandPalette = false
    @State private var isZenMode = false
    @State private var splitOrientation: SplitOrientation = .none

    @State private var paletteDataSource = DefaultPaletteDataSource()
    @State private var renderer: TextEditorRenderer?
    @State private var tabFileMap: [ULID: URL] = [:]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Tab bar — ONLY when 2+ tabs (TextMate hides it for single files)
            if tabs.count > 1 && !isZenMode {
                TabBarView(tabs: $tabs, selectedTabID: $selectedTabID) { id in
                    closeTab(id)
                }
            }

            // Dark border between title bar and editor (TextMate has this)
            Rectangle()
                .fill(Color.black.opacity(0.6))
                .frame(height: 1)

            // Editor content
            editorContent
                .overlay { commandPaletteOverlay }

            // Status bar — always visible except zen mode
            if !isZenMode {
                StatusBarView(state: {
                    var s = statusBarState
                    s.selectionString = editorState.cursorPositionString
                    return s
                }())
            }
        }
        .focusable()
        .frame(minWidth: 500, minHeight: 300)
        .onChange(of: selectedTabID) { _, _ in updateWindowTitle() }
        .onAppear { updateWindowTitle() }
        .onAppear { selectedTabID = tabs.first?.id }
        .onReceive(NotificationCenter.default.publisher(for: .sw3tToggleSidebar)) { _ in
            withAnimation(.easeOut(duration: 0.15)) { showSidebar.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sw3tToggleCommandPalette)) { _ in
            showCommandPalette.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sw3tToggleZenMode)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { isZenMode.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sw3tSplitVertical)) { _ in
            withAnimation(.spring(duration: 0.15)) {
                splitOrientation = splitOrientation == .vertical ? .none : .vertical
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sw3tSplitHorizontal)) { _ in
            withAnimation(.spring(duration: 0.15)) {
                splitOrientation = splitOrientation == .horizontal ? .none : .horizontal
            }
        }
    }

    // MARK: - Editor Content (sidebar + editor area)

    @ViewBuilder
    private var editorContent: some View {
        if showSidebar && !isZenMode {
            HSplitView {
                sidebarView
                    .frame(minWidth: 150, idealWidth: 250, maxWidth: 400)
                editorPane
            }
        } else {
            editorPane
        }
    }

    // MARK: - Editor Pane (gutter + text)

    @ViewBuilder
    private var editorPane: some View {
        HStack(spacing: 0) {
            // Gutter — matches TextMate: narrow, right-aligned, subtle background
            gutterView
            // 1px gutter border — clearly visible like TextMate
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
            // Text area
            textArea
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// Gutter — TextMate style:
    /// - Entire column: visibly lighter than editor (controlBackgroundColor)
    /// - Active line: even lighter highlight band
    /// - Numbers: right-aligned, compact
    @ViewBuilder
    private var gutterView: some View {
        let lineCount = max(editorState.lineCount, 1)
        let activeLine = editorState.currentLine + 1

        VStack(alignment: .trailing, spacing: 0) {
            ForEach(1...lineCount, id: \.self) { num in
                Text("\(num)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(num == activeLine ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 6)
                    .frame(height: 22)
                    .background(num == activeLine ? Color.primary.opacity(0.1) : Color.clear)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .frame(width: 44)
        // Entire gutter column: clearly lighter than editor area
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Text area — monospace, system colors.
    @ViewBuilder
    private var textArea: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .textBackgroundColor)

            ScrollView([.vertical, .horizontal]) {
                Text(editorState.text.isEmpty ? " " : editorState.text)
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(5) // Match the 22px line height from the gutter
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 8)
                    .padding(.top, 4)
            }

            // Invisible keyboard input capture
            TextInputBridgeView(inputHandler: editorState)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }

    // MARK: - Command Palette Overlay

    @ViewBuilder
    private var commandPaletteOverlay: some View {
        if showCommandPalette {
            VStack {
                CommandPaletteView(
                    isPresented: $showCommandPalette,
                    dataSource: paletteDataSource
                )
                .padding(.top, 40)
                Spacer()
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
            .animation(.spring(duration: 0.15), value: showCommandPalette)
            .zIndex(100)
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarView: some View {
        if project.fileTree.isEmpty {
            VStack {
                Spacer()
                Text("Open a folder to start")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                Button("Open Folder...") { openFolderDialog() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .font(.system(size: 12))
                Spacer()
            }
        } else {
            let fileNodes = project.fileTree.map { treeNodeToFileNode($0) }
            FileBrowserView(root: fileNodes, selection: $fileSelection) { node in
                openFileFromNode(node)
            }
        }
    }

    /// Set window title directly on NSWindow — centered like TextMate.
    private func updateWindowTitle() {
        let title = tabs.first(where: { $0.id == selectedTabID })?.title ?? "untitled"
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
            window.title = title
            // Remove the toolbar title to prevent SwiftUI from left-aligning it
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
        }
    }

    // MARK: - Actions

    private func openFolderDialog() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            try? project.openFolder(url)
        }
    }

    private func openFileFromNode(_ node: FileNode) {
        guard let treeNode = findTreeNode(named: node.name, in: project.fileTree) else { return }
        guard let content = try? FileService().readFile(at: treeNode.url) else { return }
        editorState.loadText(content)

        if let existing = tabs.first(where: { $0.title == node.name }) {
            selectedTabID = existing.id
        } else if let previewIdx = tabs.firstIndex(where: { $0.isPreview }) {
            tabs[previewIdx] = TabItem(title: node.name, isPreview: true)
            selectedTabID = tabs[previewIdx].id
            tabFileMap[tabs[previewIdx].id] = treeNode.url
        } else {
            let tab = TabItem(title: node.name, isPreview: true)
            tabs.append(tab)
            selectedTabID = tab.id
            tabFileMap[tab.id] = treeNode.url
        }
        statusBarState.grammarName = languageRegistry.displayName(for: treeNode.url.lastPathComponent)
    }

    private func closeTab(_ id: ULID) {
        guard !(tabs.first(where: { $0.id == id })?.isPinned ?? false) else { return }
        tabs.removeAll { $0.id == id }
        tabFileMap.removeValue(forKey: id)
        if selectedTabID == id {
            selectedTabID = tabs.last?.id
            editorState.loadText(selectedTabID.flatMap({ tabFileMap[$0] }).flatMap({ try? FileService().readFile(at: $0) }) ?? "")
        }
    }

    private func treeNodeToFileNode(_ node: FileTreeNode) -> FileNode {
        FileNode(name: node.name, isDirectory: node.isDirectory,
                 children: node.isDirectory ? node.children.map { treeNodeToFileNode($0) } : nil)
    }

    private func findTreeNode(named name: String, in nodes: [FileTreeNode]) -> FileTreeNode? {
        for node in nodes {
            if node.name == name { return node }
            if let found = findTreeNode(named: name, in: node.children) { return found }
        }
        return nil
    }
}
