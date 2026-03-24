// SW³ TextFellow — LSP Settings Window Controller
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Standalone window for LSP server configuration, accessible via ⌘K command palette.
// Replaces the broken Preferences pane injection approach.

import SwiftUI

@objc(SW3TLSPSettingsWindowController)
public class LSPSettingsWindowController: NSWindowController {

    @objc public static let shared = LSPSettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Language Server Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("LSPSettingsWindow")

        super.init(window: window)

        let hostingView = NSHostingView(rootView: LSPSettingsView())
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: 450, height: 300)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }
}
