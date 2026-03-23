// SW³ TextFellow — TextShaper Tests
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import CoreGraphics
@testable import SW3TRenderer

@Test func shaperProducesGlyphsForASCII() {
    let shaper = TextShaper(fontName: "Menlo", fontSize: 13.0)
    let shaped = shaper.shapeLine("Hello")

    #expect(shaped.glyphs.count == 5)
    #expect(shaped.width > 0)
    #expect(shaped.ascent > 0)
    #expect(shaped.descent > 0)
}

@Test func shaperHandlesEmptyString() {
    let shaper = TextShaper(fontName: "Menlo", fontSize: 13.0)
    let shaped = shaper.shapeLine("")

    #expect(shaped.glyphs.isEmpty)
    #expect(shaped.width == 0)
    #expect(shaped.ascent > 0) // font metrics still valid
}

@Test func shaperHandlesUnicodeEmoji() {
    let shaper = TextShaper(fontName: "Menlo", fontSize: 13.0)
    let shaped = shaper.shapeLine("Hello 🌍")

    // CoreText may produce more glyphs than characters due to font fallback
    #expect(shaped.glyphs.count >= 6)
    #expect(shaped.width > 0)
}

@Test func shaperHandlesCJK() {
    let shaper = TextShaper(fontName: "Menlo", fontSize: 13.0)
    let shaped = shaper.shapeLine("你好世界")

    #expect(shaped.glyphs.count >= 4)
    #expect(shaped.width > 0)
    // CJK glyphs are typically wider than Latin
}

@Test func shaperGlyphPositionsAreMonotonic() {
    let shaper = TextShaper(fontName: "Menlo", fontSize: 13.0)
    let shaped = shaper.shapeLine("abcdefg")

    // For a monospace font, positions should increase left-to-right
    for i in 1..<shaped.glyphs.count {
        #expect(shaped.glyphs[i].position.x > shaped.glyphs[i-1].position.x,
                "Glyph positions should increase: \(shaped.glyphs[i].position.x) > \(shaped.glyphs[i-1].position.x)")
    }
}

@Test func shaperColumnWidthIsPositive() {
    let shaper = TextShaper(fontName: "Menlo", fontSize: 13.0)
    #expect(shaper.columnWidth > 0)
}

@Test func shaperLineHeightIsPositive() {
    let shaper = TextShaper(fontName: "Menlo", fontSize: 13.0)
    #expect(shaper.lineHeight > 0)
    // For 13pt Menlo, line height is typically ~15-16pt
    #expect(shaper.lineHeight > 14)
    #expect(shaper.lineHeight < 20)
}

@Test func shaperFontMetrics() {
    let shaper = TextShaper(fontName: "Menlo", fontSize: 13.0)
    let metrics = shaper.fontMetrics

    #expect(metrics.ascent > 0)
    #expect(metrics.descent > 0)
    #expect(metrics.ascent > metrics.descent) // ascent is typically larger
}

@Test func shaperHandlesTabCharacter() {
    let shaper = TextShaper(fontName: "Menlo", fontSize: 13.0)
    let shaped = shaper.shapeLine("a\tb")

    #expect(shaped.glyphs.count >= 2) // at minimum 'a' and 'b' (tab may or may not produce a glyph)
    #expect(shaped.width > 0)
}

@Test func shaperHandlesLongLine() {
    let shaper = TextShaper(fontName: "Menlo", fontSize: 13.0)
    let longLine = String(repeating: "x", count: 500)
    let shaped = shaper.shapeLine(longLine)

    #expect(shaped.glyphs.count == 500)
    #expect(shaped.width > 0)
}
