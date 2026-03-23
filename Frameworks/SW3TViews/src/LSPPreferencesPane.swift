// SW³ TextFellow — LSP Preferences Pane
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Wraps the SwiftUI LSPSettingsView in an NSViewController that conforms
// to TextMate's PreferencesPaneProtocol, so it appears as a tab in Preferences.

import SwiftUI

@objc(SW3TLSPPreferencesPane)
public class LSPPreferencesPane: NSHostingController<LSPSettingsView> {
    @objc public init() {
        super.init(rootView: LSPSettingsView())
        self.title = "Language Servers"
    }

    @MainActor required init?(coder: NSCoder) {
        super.init(coder: coder, rootView: LSPSettingsView())
    }

    /// TextMate's PreferencesPaneProtocol requires this for the toolbar icon.
    @objc public var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "server.rack", accessibilityDescription: "Language Servers")
            ?? NSImage(named: NSImage.networkName)!
    }
}
