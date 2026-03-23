// SW³ TextFellow — Status Bar View
// SPDX-License-Identifier: GPL-3.0-or-later
//
// TextMate layout:
//  Line:    5:6 │ Plain Text  ◇ │ Tab Size:  4 ∨ │ ⊙ ◇ │ symbol text  ◇ │ ●

import SwiftUI

public struct StatusBarState: Sendable {
    public var line: Int = 1
    public var column: Int = 1
    public var selectionString: String = "1"
    public var grammarName: String = "Plain Text"
    public var tabSize: Int = 4
    public var softTabs: Bool = true
    public var symbolName: String = ""
    public var isMacroRecording: Bool = false

    public init() {}
}

public struct StatusBarView: View {
    let state: StatusBarState

    public init(state: StatusBarState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Line: {number}
            lineSection

            sep()

            // Plain Text ◇
            grammarSection

            sep()

            // Tab Size: 4 ∨
            tabSizeSection

            sep()

            // ⊙ ◇
            bundleItemsSection

            sep()

            // symbol area ... ◇
            symbolSection

            sep()

            // ●
            macroSection
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(height: 23)
        .background(.bar)
        .overlay(alignment: .top) {
            Color(nsColor: .separatorColor).frame(height: 1)
        }
    }

    // MARK: - Sections

    private var lineSection: some View {
        HStack(spacing: 0) {
            Text("Line:")
                .padding(.leading, 8)
            Spacer()
            Text(state.selectionString)
                .padding(.trailing, 6)
        }
        .frame(width: 100)
    }

    private var grammarSection: some View {
        HStack(spacing: 0) {
            Text(state.grammarName)
                .lineLimit(1)
                .padding(.leading, 8)
            Spacer()
            upDownChevron
                .padding(.trailing, 6)
        }
        .frame(minWidth: 130, maxWidth: 200)
    }

    private var tabSizeSection: some View {
        HStack(spacing: 3) {
            Text("Tab Size:")
            Text("\(state.tabSize)")
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
        }
        .padding(.horizontal, 8)
    }

    private var bundleItemsSection: some View {
        HStack(spacing: 2) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12))
            upDownChevron
        }
        .padding(.horizontal, 6)
    }

    private var symbolSection: some View {
        HStack(spacing: 0) {
            Text(state.symbolName)
                .lineLimit(1)
                .padding(.leading, 6)
            Spacer(minLength: 4)
            upDownChevron
                .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var macroSection: some View {
        Circle()
            .fill(state.isMacroRecording ? Color.red : Color.red.opacity(0.45))
            .frame(width: 12, height: 12)
            .padding(.horizontal, 8)
    }

    // MARK: - Shared

    private var upDownChevron: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 8, weight: .bold))
    }

    private func sep() -> some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .padding(.vertical, 5)
    }
}
