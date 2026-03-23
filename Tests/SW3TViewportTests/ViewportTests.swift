import Testing
@testable import SW3TViewport
import SW3TTextEngine
import SW3TSyntax
import CoreGraphics

@Test func renderLineConstruction() {
    let line = RenderLine(
        lineNumber: 1,
        text: "Hello",
        tokens: [],
        selections: [],
        baseline: 14.0
    )
    #expect(line.lineNumber == 1)
    #expect(line.text == "Hello")
}

@Test func documentViewportReturnsVisibleLines() {
    let snapshot = TextStorageSnapshot(
        text: "line 0\nline 1\nline 2\nline 3\nline 4",
        lineCount: 5
    )

    let viewport = DocumentViewport(
        lineHeight: 20.0,
        textProvider: { snapshot },
        highlightProvider: { _ in [] },
        selectionProvider: { [] },
        cursorProvider: { [] }
    )

    // Visible rect covers lines 1-2 (y: 20..60)
    let lines = viewport.visibleContent(in: CGRect(x: 0, y: 20, width: 800, height: 40))

    #expect(lines.count == 2)
    #expect(lines[0].lineNumber == 1)
    #expect(lines[0].text == "line 1")
    #expect(lines[1].lineNumber == 2)
    #expect(lines[1].text == "line 2")
}

@Test func documentViewportEmptyDocument() {
    let snapshot = TextStorageSnapshot(text: "", lineCount: 1)

    let viewport = DocumentViewport(
        textProvider: { snapshot },
        highlightProvider: { _ in [] },
        selectionProvider: { [] },
        cursorProvider: { [] }
    )

    let lines = viewport.visibleContent(in: CGRect(x: 0, y: 0, width: 800, height: 600))
    #expect(lines.count == 1)
    #expect(lines[0].text == "")
}

@Test func documentViewportPassesThroughCursors() {
    let snapshot = TextStorageSnapshot(text: "test", lineCount: 1)
    let cursors = [CGPoint(x: 10, y: 5), CGPoint(x: 50, y: 5)]

    let viewport = DocumentViewport(
        textProvider: { snapshot },
        highlightProvider: { _ in [] },
        selectionProvider: { [] },
        cursorProvider: { cursors }
    )

    let result = viewport.cursorPositions()
    #expect(result.count == 2)
    #expect(result[0].x == 10)
    #expect(result[1].x == 50)
}

@Test func documentViewportIntegratesTokens() {
    let snapshot = TextStorageSnapshot(text: "let x = 42", lineCount: 1)
    let tokens = [
        HighlightToken(range: 0..<3, scope: "keyword"),
        HighlightToken(range: 4..<5, scope: "variable"),
        HighlightToken(range: 8..<10, scope: "number"),
    ]

    let viewport = DocumentViewport(
        textProvider: { snapshot },
        highlightProvider: { _ in tokens },
        selectionProvider: { [] },
        cursorProvider: { [] }
    )

    let lines = viewport.visibleContent(in: CGRect(x: 0, y: 0, width: 800, height: 20))
    #expect(lines.count == 1)
    #expect(lines[0].tokens.count == 3)
    #expect(lines[0].tokens[0].scope == "keyword")
}
