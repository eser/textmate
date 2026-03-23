// SW3 TextFellow — Command Palette
// SPDX-License-Identifier: GPL-3.0-or-later
//
// AppKit-based command palette (Cmd+Shift+P). Floating NSPanel with
// fuzzy-filtered search field and results table. Designed to be called
// from existing ObjC++ code via @objc.

import AppKit

// MARK: - Data Model

/// A single command palette entry.
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

/// Command palette window controller. Presents a floating panel with a
/// search field and filterable results list.
///
/// Usage from ObjC++:
///     [[CommandPaletteController shared] showPalette];
///
@MainActor
@objc public final class CommandPaletteController: NSWindowController {

    // MARK: - Singleton

    @objc public static let shared = CommandPaletteController()

    // MARK: - Constants

    private static let panelWidth: CGFloat = 500
    private static let panelMaxHeight: CGFloat = 300
    private static let searchFieldHeight: CGFloat = 32
    private static let rowHeight: CGFloat = 28

    // MARK: - State

    private var allItems: [CommandItem] = []
    private var filteredItems: [CommandItem] = []

    // MARK: - Views

    private let searchField = NSTextField()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    // MARK: - Init

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0, y: 0,
                width: Self.panelWidth,
                height: Self.panelMaxHeight
            ),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        super.init(window: panel)

        setupSearchField()
        setupTableView()
        layoutViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Public API

    /// Register command items.
    public func registerItems(_ items: [CommandItem]) {
        allItems = items
        filteredItems = items
        tableView.reloadData()
    }

    /// Convenience to register from ObjC using dictionaries.
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
            id: id,
            title: title,
            category: category,
            shortcut: shortcut,
            action: { [weak weakTarget] in
                guard let t = weakTarget else { return }
                _ = t.perform(selector)
            }
        )
        allItems.append(item)
        filteredItems = allItems
        tableView.reloadData()
    }

    /// Show the palette, centered horizontally on the main screen.
    @objc public func showPalette() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        let panelX = screenFrame.midX - Self.panelWidth / 2
        let panelY = screenFrame.maxY - Self.panelMaxHeight - 100 // near top

        window?.setFrame(
            NSRect(
                x: panelX, y: panelY,
                width: Self.panelWidth,
                height: Self.panelMaxHeight
            ),
            display: true
        )

        filteredItems = allItems
        searchField.stringValue = ""
        tableView.reloadData()

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
    }

    /// Dismiss the palette.
    @objc public func dismissPalette() {
        close()
    }

    // MARK: - View Setup

    private func setupSearchField() {
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Type a command..."
        searchField.font = NSFont.systemFont(ofSize: 15)
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
    }

    private func setupTableView() {
        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        titleColumn.title = "Command"
        titleColumn.width = Self.panelWidth * 0.55

        let categoryColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("category"))
        categoryColumn.title = "Category"
        categoryColumn.width = Self.panelWidth * 0.2

        let shortcutColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        shortcutColumn.title = "Shortcut"
        shortcutColumn.width = Self.panelWidth * 0.2

        tableView.addTableColumn(titleColumn)
        tableView.addTableColumn(categoryColumn)
        tableView.addTableColumn(shortcutColumn)

        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 8, height: 2)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(tableDoubleClick(_:))
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
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: Self.searchFieldHeight),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    // MARK: - Filtering

    /// Simple substring-based fuzzy match.
    private func fuzzyMatch(_ query: String, in text: String) -> Bool {
        if query.isEmpty { return true }
        let lowerQuery = query.lowercased()
        let lowerText = text.lowercased()

        // Substring match
        if lowerText.contains(lowerQuery) { return true }

        // Character-by-character fuzzy match
        var queryIndex = lowerQuery.startIndex
        for char in lowerText {
            if char == lowerQuery[queryIndex] {
                queryIndex = lowerQuery.index(after: queryIndex)
                if queryIndex == lowerQuery.endIndex { return true }
            }
        }
        return false
    }

    private func applyFilter(_ query: String) {
        if query.isEmpty {
            filteredItems = allItems
        } else {
            filteredItems = allItems.filter { item in
                fuzzyMatch(query, in: item.title)
                    || fuzzyMatch(query, in: item.category)
            }
        }
        tableView.reloadData()

        // Auto-select first row if available
        if !filteredItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    // MARK: - Actions

    @objc private func searchFieldAction(_ sender: Any?) {
        executeSelectedItem()
    }

    @objc private func tableDoubleClick(_ sender: Any?) {
        executeSelectedItem()
    }

    private func executeSelectedItem() {
        let row = tableView.selectedRow
        guard row >= 0 && row < filteredItems.count else { return }
        let item = filteredItems[row]
        dismissPalette()
        item.action()
    }
}

// MARK: - NSTextFieldDelegate

extension CommandPaletteController: NSTextFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }

    /// Handle arrow keys and Return in the search field.
    public func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            let nextRow = min(tableView.selectedRow + 1, filteredItems.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(nextRow)
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            let prevRow = max(tableView.selectedRow - 1, 0)
            tableView.selectRowIndexes(IndexSet(integer: prevRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(prevRow)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            executeSelectedItem()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismissPalette()
            return true
        }
        return false
    }
}

// MARK: - NSTableViewDataSource

extension CommandPaletteController: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }
}

// MARK: - NSTableViewDelegate

extension CommandPaletteController: NSTableViewDelegate {
    public func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard row < filteredItems.count else { return nil }
        let item = filteredItems[row]

        let cellID = NSUserInterfaceItemIdentifier("CommandCell")
        let cell: NSTextField
        if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? NSTextField {
            cell = reused
        } else {
            cell = NSTextField(labelWithString: "")
            cell.identifier = cellID
            cell.isEditable = false
            cell.isBordered = false
            cell.drawsBackground = false
            cell.lineBreakMode = .byTruncatingTail
        }

        switch tableColumn?.identifier.rawValue {
        case "title":
            cell.stringValue = item.title
            cell.font = NSFont.systemFont(ofSize: 13)
            cell.textColor = NSColor.labelColor
        case "category":
            cell.stringValue = item.category
            cell.font = NSFont.systemFont(ofSize: 11)
            cell.textColor = NSColor.secondaryLabelColor
        case "shortcut":
            cell.stringValue = item.shortcut ?? ""
            cell.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            cell.textColor = NSColor.tertiaryLabelColor
            cell.alignment = .right
        default:
            break
        }

        return cell
    }
}
