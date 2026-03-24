// SW³ TextFellow — Command Palette
// SPDX-License-Identifier: GPL-3.0-or-later
//
// AppKit command palette (⌘K). Appears inside the active window,
// snapped to the top center of the key window's content area.

import AppKit

// MARK: - Data Model

public struct CommandItem: Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let shortcut: String?
    public let action: @Sendable @MainActor () -> Void

    public init(
        id: String,
        title: String,
        category: String,
        shortcut: String? = nil,
        action: @escaping @Sendable @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.shortcut = shortcut
        self.action = action
    }
}

// MARK: - Controller

@MainActor
@objc public final class CommandPaletteController: NSWindowController {

    @objc public static let shared = CommandPaletteController()

    private static let paletteWidth: CGFloat = 480
    private static let maxVisibleRows: Int = 10
    private static let searchHeight: CGFloat = 28
    private static let rowHeight: CGFloat = 28
    private static let padding: CGFloat = 12

    private var allItems: [CommandItem] = []
    private var filteredItems: [CommandItem] = []

    private let searchField = NSSearchField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    // MARK: - Init

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.paletteWidth, height: Self.panelHeight(forRowCount: Self.maxVisibleRows)),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = false

        super.init(window: panel)
        setupSearchField()
        setupTableView()
        layoutViews()

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification, object: panel
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func panelHeight(forRowCount count: Int) -> CGFloat {
        padding + searchHeight + 6 + CGFloat(count) * rowHeight + padding
    }

    // MARK: - Public API

    public func registerItems(_ items: [CommandItem]) {
        allItems = items
        filteredItems = items
        tableView.reloadData()
    }

    @objc public func registerItem(
        id: String,
        title: String,
        category: String,
        shortcut: String?,
        target: AnyObject?,
        selector: Selector
    ) {
        let weakTarget = target
        let item = CommandItem(
            id: id, title: title, category: category, shortcut: shortcut,
            action: {
                NSApp.sendAction(selector, to: nil, from: nil)
            }
        )
        allItems.append(item)
        filteredItems = allItems
        tableView.reloadData()
    }

    @objc public func registerItemWithBlock(
        id: String,
        title: String,
        category: String,
        shortcut: String?,
        actionBlock: @escaping @Sendable () -> Void
    ) {
        let item = CommandItem(
            id: id, title: title, category: category, shortcut: shortcut,
            action: { actionBlock() }
        )
        allItems.append(item)
        filteredItems = allItems
        tableView.reloadData()
    }

    /// Show the palette snapped to the top center of the key window.
    @objc public func showPalette() {
        // Snap to active window, fall back to screen center
        let hostFrame: NSRect
        if let keyWindow = NSApp.keyWindow, keyWindow !== window {
            hostFrame = keyWindow.frame
        } else if let mainWindow = NSApp.mainWindow {
            hostFrame = mainWindow.frame
        } else if let screen = NSScreen.main {
            hostFrame = screen.visibleFrame
        } else {
            return
        }

        let visibleRows = min(allItems.count, Self.maxVisibleRows)
        let totalHeight = Self.panelHeight(forRowCount: visibleRows)

        let x = hostFrame.midX - Self.paletteWidth / 2
        let y = hostFrame.maxY - totalHeight - 40

        window?.setFrame(
            NSRect(x: x, y: y, width: Self.paletteWidth, height: totalHeight),
            display: true
        )

        filteredItems = allItems
        searchField.stringValue = ""
        tableView.reloadData()
        if !filteredItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
    }

    @objc public func dismissPalette() {
        close()
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        dismissPalette()
    }

    // MARK: - View Setup

    private func setupSearchField() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Type to search files, > commands, @ symbols, : line, ! AI edit"
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.focusRingType = .none
        searchField.delegate = self
        // Don't set target/action — NSSearchField sends action after a delay.
        // Return key is handled via control(_:textView:doCommandBy:) instead.
    }

    private func setupTableView() {
        // Single column — we draw the full row ourselves via NSView-based cells
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        column.width = Self.paletteWidth
        tableView.addTableColumn(column)

        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(tableDoubleClick(_:))
        tableView.action = #selector(tableClick(_:))
        tableView.target = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
    }

    private func layoutViews() {
        guard let contentView = window?.contentView else { return }
        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: Self.searchHeight),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    // MARK: - Prefix Modes
    //
    // (none) = files (delegates to Go To File)
    // >      = commands (filters registered items)
    // @      = symbols (delegates to Symbol Chooser)
    // :      = go to line number
    // !      = AI edit (sends selected text + prompt to AI extension)
    // #      = workspace symbols (future)

    private enum PaletteMode {
        case files
        case commands
        case symbols
        case goToLine
        case aiEdit
    }

    private var currentMode: PaletteMode = .commands

    private func detectMode(from query: String) -> (PaletteMode, String) {
        if query.hasPrefix(">") {
            return (.commands, String(query.dropFirst()).trimmingCharacters(in: .whitespaces))
        } else if query.hasPrefix("@") {
            return (.symbols, String(query.dropFirst()).trimmingCharacters(in: .whitespaces))
        } else if query.hasPrefix(":") {
            return (.goToLine, String(query.dropFirst()).trimmingCharacters(in: .whitespaces))
        } else if query.hasPrefix("!") {
            return (.aiEdit, String(query.dropFirst()).trimmingCharacters(in: .whitespaces))
        } else {
            return (.files, query)
        }
    }

    // MARK: - Filtering

    private func fuzzyMatch(_ query: String, in text: String) -> Bool {
        if query.isEmpty { return true }
        let q = query.lowercased(), t = text.lowercased()
        if t.contains(q) { return true }
        var qi = q.startIndex
        for ch in t {
            if ch == q[qi] {
                qi = q.index(after: qi)
                if qi == q.endIndex { return true }
            }
        }
        return false
    }

    private func applyFilter(_ query: String) {
        let (mode, stripped) = detectMode(from: query)
        currentMode = mode

        switch mode {
        case .commands:
            filteredItems = stripped.isEmpty ? allItems : allItems.filter {
                fuzzyMatch(stripped, in: $0.title) || fuzzyMatch(stripped, in: $0.category)
            }
            tableView.reloadData()
            if !filteredItems.isEmpty {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }

        case .files:
            // Show hint row, delegate to Go To File on execute
            filteredItems = [CommandItem(
                id: "_hint_files", title: "Search files: \(stripped)", category: "Go To File",
                shortcut: "⌘T", action: { NSApp.sendAction(Selector("goToFile:"), to: nil, from: nil) }
            )]
            tableView.reloadData()
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        case .symbols:
            filteredItems = [CommandItem(
                id: "_hint_symbols", title: "Search symbols: \(stripped)", category: "Jump to Symbol",
                shortcut: "⇧⌘T", action: { NSApp.sendAction(Selector("showSymbolChooser:"), to: nil, from: nil) }
            )]
            tableView.reloadData()
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        case .goToLine:
            filteredItems = [CommandItem(
                id: "_hint_line", title: "Go to line \(stripped)", category: "Navigate",
                shortcut: "⌘L", action: { NSApp.sendAction(Selector("orderFrontGoToLinePanel:"), to: nil, from: nil) }
            )]
            tableView.reloadData()
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        case .aiEdit:
            let prompt = stripped
            filteredItems = [CommandItem(
                id: "_ai_edit", title: prompt.isEmpty ? "Type your edit instruction…" : "AI Edit: \(prompt)",
                category: "AI",
                shortcut: nil,
                action: { [weak self] in
                    guard !prompt.isEmpty else { return }
                    // Dispatch AI edit request via AIEditManager
                    let mgr = NSClassFromString("SW3TAIEditManager")
                    if let shared = mgr?.value(forKey: "shared") as? NSObject {
                        shared.perform(
                            NSSelectorFromString("requestEditWithSelectedText:prompt:filePath:language:completion:"),
                            with: "" as NSString, with: prompt as NSString
                        )
                    }
                }
            )]
            tableView.reloadData()
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    // MARK: - Actions

    @objc private func tableClick(_ sender: Any?) { executeSelectedItem() }
    @objc private func tableDoubleClick(_ sender: Any?) { executeSelectedItem() }

    private func executeSelectedItem() {
        let row = tableView.selectedRow
        guard row >= 0 && row < filteredItems.count else { return }
        let item = filteredItems[row]
        dismissPalette()
        item.action()
    }
}

// MARK: - NSTextFieldDelegate

extension CommandPaletteController: NSSearchFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)):
            let next = min(tableView.selectedRow + 1, filteredItems.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            tableView.scrollRowToVisible(next)
            return true
        case #selector(NSResponder.moveUp(_:)):
            let prev = max(tableView.selectedRow - 1, 0)
            tableView.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
            tableView.scrollRowToVisible(prev)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            executeSelectedItem()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismissPalette()
            return true
        default:
            return false
        }
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension CommandPaletteController: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int { filteredItems.count }
}

extension CommandPaletteController: NSTableViewDelegate {
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredItems.count else { return nil }
        let item = filteredItems[row]

        let cellID = NSUserInterfaceItemIdentifier("PaletteRow")
        let rowView: PaletteRowView
        if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? PaletteRowView {
            rowView = reused
        } else {
            rowView = PaletteRowView()
            rowView.identifier = cellID
        }
        rowView.configure(title: item.title, category: item.category, shortcut: item.shortcut)
        return rowView
    }
}

// MARK: - Row View

/// Custom row view with properly aligned title, category, and shortcut.
private final class PaletteRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let categoryLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for label in [titleLabel, categoryLabel, shortcutLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.isEditable = false
            label.isBordered = false
            label.drawsBackground = false
            label.lineBreakMode = .byTruncatingTail
            addSubview(label)
        }

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        categoryLabel.font = .systemFont(ofSize: 11)
        categoryLabel.textColor = .tertiaryLabelColor
        categoryLabel.alignment = .right
        categoryLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        shortcutLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.firstBaselineAnchor.constraint(equalTo: topAnchor, constant: 19),

            categoryLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            categoryLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            categoryLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            shortcutLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            shortcutLabel.leadingAnchor.constraint(equalTo: categoryLabel.trailingAnchor, constant: 12),
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            shortcutLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, category: String, shortcut: String?) {
        titleLabel.stringValue = title
        categoryLabel.stringValue = category
        shortcutLabel.stringValue = shortcut ?? ""
    }
}
