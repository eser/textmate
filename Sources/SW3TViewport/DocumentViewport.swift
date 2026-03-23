// SW³ TextFellow — Document Viewport
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import CoreText
import SW3TTextEngine
import SW3TSyntax

/// Concrete ViewportProvider that bridges SW3TDocument state to the renderer.
///
/// ```
///  Data Flow:
///
///  TextStorageSnapshot ──► visible lines extraction
///        │
///  SyntaxHighlighter  ──► tokens for visible range
///        │
///  Selection state    ──► selection ranges per line
///        │
///        ▼
///  [RenderLine] array ──► SW3TRenderer
/// ```
///
/// This is a stateless view-model — it reads from document state
/// and produces frame-ready data. No mutation, no side effects.
public final class DocumentViewport: ViewportProvider {
    private let textProvider: @Sendable () -> TextStorageSnapshot
    private let highlightProvider: @Sendable (Range<Int>) -> [HighlightToken]
    private let selectionProvider: @Sendable () -> [Range<Int>]
    private let cursorProvider: @Sendable () -> [CGPoint]

    /// Line height in points.
    public let lineHeight: CGFloat

    /// Left padding (gutter width) in points.
    public let gutterWidth: CGFloat

    public init(
        lineHeight: CGFloat = 20.0,
        gutterWidth: CGFloat = 50.0,
        textProvider: @escaping @Sendable () -> TextStorageSnapshot,
        highlightProvider: @escaping @Sendable (Range<Int>) -> [HighlightToken],
        selectionProvider: @escaping @Sendable () -> [Range<Int>],
        cursorProvider: @escaping @Sendable () -> [CGPoint]
    ) {
        self.lineHeight = lineHeight
        self.gutterWidth = gutterWidth
        self.textProvider = textProvider
        self.highlightProvider = highlightProvider
        self.selectionProvider = selectionProvider
        self.cursorProvider = cursorProvider
    }

    // MARK: - ViewportProvider

    public func visibleContent(in rect: CGRect) -> [RenderLine] {
        let snapshot = textProvider()
        let selections = selectionProvider()

        // Determine visible line range from rect
        let firstVisibleLine = max(0, Int(floor(rect.minY / lineHeight)))
        let lastVisibleLine = min(snapshot.lineCount - 1, Int(ceil(rect.maxY / lineHeight)) - 1)

        guard firstVisibleLine <= lastVisibleLine else { return [] }

        // Get text lines
        let lines = snapshot.text.split(separator: "\n", omittingEmptySubsequences: false)

        var renderLines: [RenderLine] = []
        renderLines.reserveCapacity(lastVisibleLine - firstVisibleLine + 1)

        for lineNum in firstVisibleLine...lastVisibleLine {
            let lineText: String
            if lineNum < lines.count {
                lineText = String(lines[lineNum])
            } else {
                lineText = ""
            }

            // Get tokens for this line's range
            let lineStartOffset = offsetForLine(lineNum, in: snapshot.text)
            let lineEndOffset = lineStartOffset + lineText.utf8.count
            let tokens: [HighlightToken]
            if lineStartOffset < lineEndOffset {
                tokens = highlightProvider(lineStartOffset..<lineEndOffset)
            } else {
                tokens = []
            }

            // Filter selections that intersect this line
            let lineSelections = selections.filter { sel in
                sel.lowerBound < lineEndOffset && sel.upperBound > lineStartOffset
            }.map { sel in
                // Clamp to line bounds and make line-relative
                let start = max(sel.lowerBound - lineStartOffset, 0)
                let end = min(sel.upperBound - lineStartOffset, lineText.utf8.count)
                return start..<end
            }

            let baseline = CGFloat(lineNum) * lineHeight + lineHeight * 0.8

            renderLines.append(RenderLine(
                lineNumber: lineNum,
                text: lineText,
                tokens: tokens,
                selections: lineSelections,
                baseline: baseline
            ))
        }

        return renderLines
    }

    public func cursorPositions() -> [CGPoint] {
        cursorProvider()
    }

    // MARK: - Helpers

    /// Calculate the UTF-8 byte offset of the start of a given line number.
    private func offsetForLine(_ lineNumber: Int, in text: String) -> Int {
        var offset = 0
        var currentLine = 0
        for byte in text.utf8 {
            if currentLine == lineNumber { break }
            offset += 1
            if byte == UInt8(ascii: "\n") {
                currentLine += 1
            }
        }
        return offset
    }
}
