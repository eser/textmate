// SW³ TextFellow — Zen Mode
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Distraction-free writing mode. ⌘⇧↩ to toggle, Escape to exit.
//
// When activated:
//  - Tab bar, status bar, sidebar, all panels fade out (~200ms)
//  - Text area expands to fill the window
//  - Generous horizontal margins center the text
//  - No jarring reflow — cursor stays in place
//
// Animation hard rule: <200ms, never blocking.
// User can type/click during any animation — it completes instantly.

import SwiftUI

/// View modifier that wraps content in zen mode support.
public struct ZenModeModifier: ViewModifier {
    @Binding var isZenMode: Bool

    /// Horizontal margin in zen mode (centers the text).
    let zenMargin: CGFloat = 120

    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, isZenMode ? zenMargin : 0)
            .animation(.easeOut(duration: 0.2), value: isZenMode)
            .onKeyPress(.escape) {
                if isZenMode {
                    isZenMode = false
                    return .handled
                }
                return .ignored
            }
    }
}

public extension View {
    /// Apply zen mode support. When active, adds horizontal margins.
    func zenMode(_ isActive: Binding<Bool>) -> some View {
        modifier(ZenModeModifier(isZenMode: isActive))
    }
}
