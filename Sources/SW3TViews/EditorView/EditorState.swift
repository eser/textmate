// SW³ TextFellow — Editor State
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Observable state that bridges keyboard input → TextStorage → Metal rendering.
// This is the "coordinator" between the invisible TextInputBridge
// and the visible MetalEditorView.

import SwiftUI
import SW3TTextEngine
import SW3TViewport
import SW3TSyntax

/// Observable editor state for a single editor pane.
///
/// ```
///  TextInputBridge ──► EditorState (TextInputHandler)
///       │                    │
///       │  keystrokes        │  mutations
///       ▼                    ▼
///  insertText()  ──► storage.insert()
///  deleteBackward()  ──► storage.delete()
///       │
///       ▼
///  text changed ──► DocumentViewport ──► Metal renderer
/// ```
@Observable
public final class EditorState: TextInputHandler {
    /// The current text content.
    public private(set) var text: String

    /// Cursor byte offset in the text.
    public private(set) var cursorOffset: Int = 0

    /// Number of lines.
    public var lineCount: Int {
        text.isEmpty ? 1 : text.filter { $0 == "\n" }.count + 1
    }

    /// Current line number (0-based).
    public var currentLine: Int {
        text.prefix(cursorOffset).filter { $0 == "\n" }.count
    }

    /// Current column (0-based, in characters from line start).
    public var currentColumn: Int {
        let beforeCursor = String(text.prefix(cursorOffset))
        if let lastNewline = beforeCursor.lastIndex(of: "\n") {
            return beforeCursor.distance(from: beforeCursor.index(after: lastNewline), to: beforeCursor.endIndex)
        }
        return cursorOffset
    }

    /// Status bar display string — TextMate format:
    /// Single cursor: "1" (just line number)
    /// With column: "1:5" (line:column)
    /// Selection: "1-5:6" (startLine-endLine:column)
    public var cursorPositionString: String {
        let line = currentLine + 1
        let col = currentColumn + 1
        if col > 1 {
            return "\(line):\(col)"
        }
        return "\(line)"
    }

    public init(text: String = "") {
        self.text = text
        self.cursorOffset = 0
    }

    /// Load new content (e.g., when opening a file).
    public func loadText(_ newText: String) {
        text = newText
        cursorOffset = 0
    }

    // MARK: - TextInputHandler

    public func insertText(_ string: String) {
        let idx = text.index(text.startIndex, offsetBy: min(cursorOffset, text.count))
        text.insert(contentsOf: string, at: idx)
        cursorOffset += string.count
    }

    public func deleteBackward() {
        guard cursorOffset > 0 else { return }
        let idx = text.index(text.startIndex, offsetBy: cursorOffset)
        let prevIdx = text.index(before: idx)
        text.remove(at: prevIdx)
        cursorOffset -= 1
    }

    public func deleteForward() {
        guard cursorOffset < text.count else { return }
        let idx = text.index(text.startIndex, offsetBy: cursorOffset)
        text.remove(at: idx)
    }

    public func moveUp() {
        // Move to same column on previous line
        guard currentLine > 0 else { return }
        let col = currentColumn
        let targetLine = currentLine - 1
        cursorOffset = offsetForLine(targetLine) + min(col, lengthOfLine(targetLine))
    }

    public func moveDown() {
        guard currentLine < lineCount - 1 else { return }
        let col = currentColumn
        let targetLine = currentLine + 1
        cursorOffset = offsetForLine(targetLine) + min(col, lengthOfLine(targetLine))
    }

    public func moveLeft() {
        if cursorOffset > 0 { cursorOffset -= 1 }
    }

    public func moveRight() {
        if cursorOffset < text.count { cursorOffset += 1 }
    }

    public func moveToBeginningOfLine() {
        cursorOffset = offsetForLine(currentLine)
    }

    public func moveToEndOfLine() {
        cursorOffset = offsetForLine(currentLine) + lengthOfLine(currentLine)
    }

    public func insertNewline() {
        insertText("\n")
    }

    public func insertTab() {
        insertText("    ") // 4 spaces (soft tabs, TextMate default)
    }

    // MARK: - Viewport

    /// Create a DocumentViewport for the current state.
    public func makeViewport() -> DocumentViewport {
        let currentText = text
        let snapshot = TextStorageSnapshot(
            text: currentText,
            lineCount: lineCount
        )
        let col = currentColumn
        let line = currentLine
        let colWidth: CGFloat = 7.8 // approximate Menlo 13pt column width

        return DocumentViewport(
            textProvider: { snapshot },
            highlightProvider: { _ in [] },
            selectionProvider: { [] },
            cursorProvider: {
                [CGPoint(x: 50.0 + CGFloat(col) * colWidth, y: CGFloat(line) * 20.0)]
            }
        )
    }

    // MARK: - Helpers

    private func offsetForLine(_ lineNumber: Int) -> Int {
        var offset = 0
        var line = 0
        for (i, char) in text.enumerated() {
            if line == lineNumber { return i }
            if char == "\n" { line += 1 }
            offset = i + 1
        }
        if line == lineNumber { return offset }
        return text.count
    }

    private func lengthOfLine(_ lineNumber: Int) -> Int {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lineNumber >= 0, lineNumber < lines.count else { return 0 }
        return lines[lineNumber].count
    }
}
