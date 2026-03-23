// SW³ TextFellow — Application Entry Point
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Uses AppKit NSWindow directly (not SwiftUI WindowGroup) to get
// proper centered title bar matching TextMate. SwiftUI content
// is embedded via NSHostingView.

import SwiftUI
import AppKit
import SW3TViews

@main
struct TextFellowApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create NSWindow with standard title bar — centered title like TextMate
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "untitled"
        window.center()
        window.setFrameAutosaveName("TextFellowMainWindow")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 300)
        window.delegate = self

        // No toolbar — TextMate has none. Strip it aggressively.
        window.toolbar = nil
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false

        // Embed SwiftUI content
        let editorView = EditorWindowView()
        let hostingView = NSHostingView(rootView: editorView)
        hostingView.safeAreaRegions = []  // Prevent safe area insets from affecting layout
        window.contentView = hostingView

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Strip toolbar again after SwiftUI has a chance to add one
        DispatchQueue.main.async { [weak self] in
            self?.window.toolbar = nil
        }

        buildMenuBar()
    }

    // Keep stripping toolbar if SwiftUI tries to re-add it
    func windowDidUpdate(_ notification: Notification) {
        if window.toolbar != nil {
            window.toolbar = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu Bar (matches TextMate exactly)
    // TextMate | File | Edit | View | Navigate | Text | File Browser | Bundles | Window | Help

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // ── App menu ──
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        appMenuItem.title = "TextFellow"
        appMenu.addItem(withTitle: "About TextFellow", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences…", action: nil, keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide TextFellow", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit TextFellow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(appMenuItem)

        // ── File ──
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New", action: nil, keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…", action: nil, keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Save", action: nil, keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Save As…", action: nil, keyEquivalent: "S")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // ── Edit ──
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findItem = editMenu.addItem(withTitle: "Find…", action: nil, keyEquivalent: "f")
        _ = findItem
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // ── View ──
        let viewMenu = NSMenu(title: "View")
        addNotificationItem(viewMenu, title: "Zen Mode", notification: .sw3tToggleZenMode, key: "\r", modifiers: [.command, .shift])
        viewMenu.addItem(.separator())
        addNotificationItem(viewMenu, title: "Split Vertically", notification: .sw3tSplitVertical, key: "\\", modifiers: [.command])
        addNotificationItem(viewMenu, title: "Split Horizontally", notification: .sw3tSplitHorizontal, key: "\\", modifiers: [.command, .option])
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // ── Navigate ──
        let navMenu = NSMenu(title: "Navigate")
        navMenu.addItem(withTitle: "Go to File…", action: nil, keyEquivalent: "t")
        navMenu.addItem(withTitle: "Go to Symbol…", action: nil, keyEquivalent: "T")
        navMenu.addItem(withTitle: "Go to Line…", action: nil, keyEquivalent: "l")
        navMenu.addItem(.separator())
        addNotificationItem(navMenu, title: "Command Palette", notification: .sw3tToggleCommandPalette, key: "k", modifiers: [.command])
        let navMenuItem = NSMenuItem()
        navMenuItem.submenu = navMenu
        mainMenu.addItem(navMenuItem)

        // ── Text ──
        let textMenu = NSMenu(title: "Text")
        textMenu.addItem(withTitle: "Transpose", action: nil, keyEquivalent: "")
        textMenu.addItem(.separator())
        textMenu.addItem(withTitle: "Shift Left", action: nil, keyEquivalent: "[")
        textMenu.addItem(withTitle: "Shift Right", action: nil, keyEquivalent: "]")
        textMenu.addItem(.separator())
        textMenu.addItem(withTitle: "Reformat Text", action: nil, keyEquivalent: "")
        textMenu.addItem(.separator())
        let filterItem = textMenu.addItem(withTitle: "Filter Through Command…", action: nil, keyEquivalent: "|")
        _ = filterItem
        let textMenuItem = NSMenuItem()
        textMenuItem.submenu = textMenu
        mainMenu.addItem(textMenuItem)

        // ── File Browser ──
        let fbMenu = NSMenu(title: "File Browser")
        addNotificationItem(fbMenu, title: "Toggle File Browser", notification: .sw3tToggleSidebar, key: "b", modifiers: [.command, .option])
        let fbMenuItem = NSMenuItem()
        fbMenuItem.submenu = fbMenu
        mainMenu.addItem(fbMenuItem)

        // ── Bundles ──
        let bundlesMenu = NSMenu(title: "Bundles")
        let noBundles = bundlesMenu.addItem(withTitle: "No bundles loaded", action: nil, keyEquivalent: "")
        noBundles.isEnabled = false
        let bundlesMenuItem = NSMenuItem()
        bundlesMenuItem.submenu = bundlesMenu
        mainMenu.addItem(bundlesMenuItem)

        // ── Window ──
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.windowsMenu = windowMenu

        // ── Help ──
        let helpMenu = NSMenu(title: "Help")
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }

    /// Helper: add a menu item that posts a notification when clicked.
    private func addNotificationItem(_ menu: NSMenu, title: String, notification: Notification.Name, key: String, modifiers: NSEvent.ModifierFlags = [.command]) {
        let item = NSMenuItem(title: title, action: #selector(handleNotificationMenuItem(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.representedObject = notification
        menu.addItem(item)
    }

    @objc private func handleNotificationMenuItem(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? Notification.Name else { return }
        NotificationCenter.default.post(name: name, object: nil)
    }
}
