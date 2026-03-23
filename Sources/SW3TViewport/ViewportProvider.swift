// SW³ TextFellow — SW3TViewport
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import SW3TTextEngine
import SW3TSyntax

/// A single line ready for Metal rendering.
public struct RenderLine: Sendable {
    public let lineNumber: Int
    public let text: String
    public let tokens: [HighlightToken]
    public let selections: [Range<Int>]
    public let baseline: CGFloat

    public init(
        lineNumber: Int,
        text: String,
        tokens: [HighlightToken],
        selections: [Range<Int>],
        baseline: CGFloat
    ) {
        self.lineNumber = lineNumber
        self.text = text
        self.tokens = tokens
        self.selections = selections
        self.baseline = baseline
    }
}

/// Protocol for providing frame-ready content to the renderer.
///
/// SW3TRenderer depends ONLY on this protocol — never on
/// SW3TTextEngine or SW3TSyntax directly.
public protocol ViewportProvider: Sendable {
    /// Returns the lines visible in the given rect, fully resolved
    /// with text content, syntax tokens, and selection ranges.
    func visibleContent(in rect: CGRect) -> [RenderLine]

    /// Returns current cursor positions for caret rendering.
    func cursorPositions() -> [CGPoint]
}
