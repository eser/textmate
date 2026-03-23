// SW³ TextFellow — UI Notification Names
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Notification names for UI toggle actions.
/// Used by SwiftUI views to respond to menu commands and keybindings.
public extension Notification.Name {
    static let sw3tToggleSidebar = Notification.Name("sw3t.toggleSidebar")
    static let sw3tToggleTerminal = Notification.Name("sw3t.toggleTerminal")
    static let sw3tToggleZenMode = Notification.Name("sw3t.toggleZenMode")
    static let sw3tToggleCommandPalette = Notification.Name("sw3t.toggleCommandPalette")
    static let sw3tSplitVertical = Notification.Name("sw3t.splitVertical")
    static let sw3tSplitHorizontal = Notification.Name("sw3t.splitHorizontal")
    static let sw3tWindowTitleChanged = Notification.Name("sw3t.windowTitleChanged")
}
