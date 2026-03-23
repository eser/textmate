// SW³ TextFellow — Command Palette
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Universal entry point for every action. Progressive disclosure:
// invisible until ⌘K, no residual chrome.
//
// Prefix modes:
//   (none) → file search (fuzzy across project)
//   >      → command search (editor, bundle, settings)
//   @      → symbol search (current file, tree-sitter/LSP)
//   :      → go to line number
//   #      → workspace symbol search (cross-file, LSP)

import SwiftUI
import SW3TTextEngine

/// The mode the command palette operates in, determined by input prefix.
public enum PaletteMode: Equatable, Sendable {
    case files          // default — fuzzy file search
    case commands       // > prefix
    case symbols        // @ prefix
    case goToLine       // : prefix
    case workspaceSymbols // # prefix

    /// Placeholder text for the search field.
    public var placeholder: String {
        switch self {
        case .files: return "Search files by name..."
        case .commands: return "Type a command..."
        case .symbols: return "Go to symbol in file..."
        case .goToLine: return "Type a line number..."
        case .workspaceSymbols: return "Search symbols across project..."
        }
    }

    /// Detect mode from current input text.
    public static func detect(from input: String) -> PaletteMode {
        if input.hasPrefix(">") { return .commands }
        if input.hasPrefix("@") { return .symbols }
        if input.hasPrefix(":") { return .goToLine }
        if input.hasPrefix("#") { return .workspaceSymbols }
        return .files
    }

    /// Strip the prefix from input to get the actual search query.
    public static func query(from input: String) -> String {
        let mode = detect(from: input)
        switch mode {
        case .files: return input
        case .commands, .symbols, .goToLine, .workspaceSymbols:
            return String(input.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
    }
}

/// A single result item in the command palette.
public struct PaletteItem: Identifiable, Sendable {
    public let id: ULID
    public let title: String
    public let subtitle: String
    public let icon: String      // SF Symbol name
    public let action: @Sendable () -> Void

    public init(
        id: ULID = ULID(),
        title: String,
        subtitle: String = "",
        icon: String = "doc",
        action: @escaping @Sendable () -> Void = {}
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.action = action
    }
}

/// Data source protocol for command palette results.
/// Different modes produce results from different sources.
public protocol PaletteDataSource: Sendable {
    func search(query: String, mode: PaletteMode) async -> [PaletteItem]
}

/// Command palette view — TextMate-style overlay.
///
/// Appears centered at the top of the editor (like TextMate's Go to File / ⌘T).
/// No state retained between invocations — fresh start every time.
public struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    let dataSource: any PaletteDataSource

    @State private var input: String = ""
    @State private var results: [PaletteItem] = []
    @State private var selectedIndex: Int = 0
    @FocusState private var isInputFocused: Bool

    private var mode: PaletteMode { .detect(from: input) }
    private var query: String { PaletteMode.query(from: input) }

    public init(isPresented: Binding<Bool>, dataSource: any PaletteDataSource) {
        self._isPresented = isPresented
        self.dataSource = dataSource
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search input — single text field, TextMate style
            HStack(spacing: 8) {
                Image(systemName: modeIcon)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                TextField(mode.placeholder, text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isInputFocused)
                    .onSubmit { executeSelected() }
                    .onChange(of: input) { _, _ in
                        selectedIndex = 0
                        Task { await performSearch() }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // 1px divider
            if !results.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 1)
            }

            // Results list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                            resultRow(item: item, isSelected: index == selectedIndex)
                                .id(index)
                                .onTapGesture { execute(item) }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .onChange(of: selectedIndex) { _, newIndex in
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        .frame(width: 500)
        .onAppear {
            input = ""
            results = []
            selectedIndex = 0
            isInputFocused = true
            Task { await performSearch() }
        }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.downArrow) { moveSelection(1); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    // MARK: - Result Row

    @ViewBuilder
    private func resultRow(item: PaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Logic

    private var modeIcon: String {
        switch mode {
        case .files: return "magnifyingglass"
        case .commands: return "chevron.right"
        case .symbols: return "at"
        case .goToLine: return "number"
        case .workspaceSymbols: return "number.square"
        }
    }

    private func performSearch() async {
        let items = await dataSource.search(query: query, mode: mode)
        results = items
        selectedIndex = min(selectedIndex, max(results.count - 1, 0))
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }

    private func executeSelected() {
        guard selectedIndex < results.count else { return }
        execute(results[selectedIndex])
    }

    private func execute(_ item: PaletteItem) {
        dismiss()
        item.action()
    }

    private func dismiss() {
        input = ""
        results = []
        isPresented = false
    }
}

// MARK: - Default Data Source

/// Built-in data source that provides basic file and command search.
/// Extended by LSP (workspace symbols) and bundle system (bundle commands).
public final class DefaultPaletteDataSource: PaletteDataSource, @unchecked Sendable {
    private var commands: [PaletteItem] = []
    private var fileProvider: (@Sendable (String) -> [PaletteItem])?

    public init() {
        registerBuiltinCommands()
    }

    /// Register a file search provider (called by ProjectModel).
    public func setFileProvider(_ provider: @escaping @Sendable (String) -> [PaletteItem]) {
        self.fileProvider = provider
    }

    /// Register an additional command.
    public func registerCommand(_ item: PaletteItem) {
        commands.append(item)
    }

    public func search(query: String, mode: PaletteMode) async -> [PaletteItem] {
        switch mode {
        case .files:
            return fileProvider?(query) ?? []

        case .commands:
            if query.isEmpty { return commands }
            return commands.filter { fuzzyMatch(query, in: $0.title) }

        case .goToLine:
            if let line = Int(query) {
                return [PaletteItem(
                    title: "Go to line \(line)",
                    icon: "arrow.right",
                    action: { /* TODO: navigate to line */ }
                )]
            }
            return []

        case .symbols, .workspaceSymbols:
            // TODO: Populated by tree-sitter (symbols) and LSP (workspace symbols)
            return []
        }
    }

    // MARK: - Built-in commands

    private func registerBuiltinCommands() {
        commands = [
            PaletteItem(title: "Toggle Sidebar", subtitle: "⌘1", icon: "sidebar.leading"),
            PaletteItem(title: "Toggle Terminal", subtitle: "⌃`", icon: "terminal"),
            PaletteItem(title: "Zen Mode", subtitle: "⌘⇧↩", icon: "eye.slash"),
            PaletteItem(title: "Split Vertically", subtitle: "⌘\\", icon: "rectangle.split.2x1"),
            PaletteItem(title: "Split Horizontally", subtitle: "⌘⌥\\", icon: "rectangle.split.1x2"),
            PaletteItem(title: "Show Scope Bar", icon: "chevron.right.2"),
            PaletteItem(title: "Toggle Typewriter Mode", icon: "text.aligncenter"),
            PaletteItem(title: "Show Undo Tree", subtitle: "⌘⌥U", icon: "arrow.uturn.backward.circle"),
            PaletteItem(title: "Change Language", icon: "textformat"),
            PaletteItem(title: "Change Encoding", icon: "doc.text"),
            PaletteItem(title: "Change Indent Style", icon: "increase.indent"),
            PaletteItem(title: "Change Line Ending", icon: "return"),
        ]
    }
}

// MARK: - Fuzzy Match

/// Simple fuzzy matching — characters must appear in order but not contiguously.
private func fuzzyMatch(_ query: String, in target: String) -> Bool {
    var queryIndex = query.lowercased().startIndex
    let queryEnd = query.lowercased().endIndex
    let targetLower = target.lowercased()

    for char in targetLower {
        if queryIndex == queryEnd { return true }
        if char == query.lowercased()[queryIndex] {
            queryIndex = query.lowercased().index(after: queryIndex)
        }
    }
    return queryIndex == queryEnd
}

#if DEBUG
#Preview("Command Palette") {
    @Previewable @State var shown = true

    ZStack {
        Color(nsColor: .textBackgroundColor)
            .ignoresSafeArea()

        if shown {
            VStack {
                CommandPaletteView(
                    isPresented: $shown,
                    dataSource: DefaultPaletteDataSource()
                )
                .padding(.top, 50)
                Spacer()
            }
        }
    }
    .frame(width: 700, height: 500)
}
#endif
