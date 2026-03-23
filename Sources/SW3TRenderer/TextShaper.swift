// SW³ TextFellow — CoreText Text Shaper
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Delegates ALL Unicode complexity to CoreText:
// ligatures, bidi, RTL, CJK, Turkish İ/ı, emoji, font fallback, OpenType.
//
// Pipeline:
//
//   String line ──► CTLine ──► [CTRun] ──► [ShapedGlyph]
//        │                                      │
//        │  CoreText handles:                   │  We extract:
//        │  - ligature substitution             │  - glyph ID (CGGlyph)
//        │  - bidi reordering                   │  - x/y position
//        │  - font fallback chains              │  - font name + size
//        │  - OpenType features                 │  - advance width
//        └──────────────────────────────────────┘

import CoreText
import CoreGraphics
import Foundation

/// A single positioned glyph produced by CoreText shaping.
public struct ShapedGlyph {
    public let glyphID: CGGlyph
    public let position: CGPoint       // Baseline-relative position
    public let advance: CGFloat        // Horizontal advance
    public let fontName: String
    public let fontSize: CGFloat
    public let runIndex: Int           // Which CTRun this came from
}

/// Result of shaping a single line of text.
public struct ShapedLine {
    public let glyphs: [ShapedGlyph]
    public let width: CGFloat          // Total typographic width
    public let ascent: CGFloat
    public let descent: CGFloat
    public let leading: CGFloat

    /// Total line height (ascent + descent + leading).
    public var height: CGFloat { ascent + descent + leading }
}

/// CoreText text shaper — converts strings to positioned glyphs.
///
/// This is the bridge between TextStorage content and the Metal renderer.
/// CoreText does all the hard work; we just extract the results.
public struct TextShaper {
    public let defaultFont: CTFont
    public let defaultFontName: String
    public let defaultFontSize: CGFloat

    public init(fontName: String = "Menlo", fontSize: CGFloat = 13.0) {
        self.defaultFontName = fontName
        self.defaultFontSize = fontSize
        self.defaultFont = CTFontCreateWithName(fontName as CFString, fontSize, nil)
    }

    /// Shape a line of text into positioned glyphs.
    ///
    /// - Parameters:
    ///   - text: The line content (single line, no newlines)
    ///   - attributes: Optional per-range attributes (for syntax coloring)
    /// - Returns: A ShapedLine with all glyphs positioned by CoreText
    public func shapeLine(_ text: String) -> ShapedLine {
        guard !text.isEmpty else {
            let ascent = CTFontGetAscent(defaultFont)
            let descent = CTFontGetDescent(defaultFont)
            let leading = CTFontGetLeading(defaultFont)
            return ShapedLine(glyphs: [], width: 0, ascent: ascent, descent: descent, leading: leading)
        }

        // Create attributed string with default font
        let attrString = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
        CFAttributedStringReplaceString(attrString, CFRangeMake(0, 0), text as CFString)
        CFAttributedStringSetAttribute(
            attrString,
            CFRangeMake(0, CFAttributedStringGetLength(attrString)),
            kCTFontAttributeName,
            defaultFont
        )

        // Create CTLine — CoreText does all shaping here
        let line = CTLineCreateWithAttributedString(attrString)

        // Extract metrics
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

        // Extract glyphs from each CTRun
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        var shapedGlyphs: [ShapedGlyph] = []

        for (runIndex, run) in runs.enumerated() {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            // Get glyph IDs
            var glyphIDs = [CGGlyph](repeating: 0, count: glyphCount)
            CTRunGetGlyphs(run, CFRangeMake(0, glyphCount), &glyphIDs)

            // Get positions
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetPositions(run, CFRangeMake(0, glyphCount), &positions)

            // Get advances
            var advances = [CGSize](repeating: .zero, count: glyphCount)
            CTRunGetAdvances(run, CFRangeMake(0, glyphCount), &advances)

            // Get the font for this run (may differ from default due to font fallback)
            let runAttributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = runAttributes[kCTFontAttributeName as String] as! CTFont
            let runFontName = CTFontCopyPostScriptName(runFont) as String
            let runFontSize = CTFontGetSize(runFont)

            for i in 0..<glyphCount {
                shapedGlyphs.append(ShapedGlyph(
                    glyphID: glyphIDs[i],
                    position: positions[i],
                    advance: advances[i].width,
                    fontName: runFontName,
                    fontSize: runFontSize,
                    runIndex: runIndex
                ))
            }
        }

        return ShapedLine(
            glyphs: shapedGlyphs,
            width: width,
            ascent: ascent,
            descent: descent,
            leading: leading
        )
    }

    /// Get the monospace column width for the default font.
    /// Used for gutter width calculation and tab stop alignment.
    public var columnWidth: CGFloat {
        var glyph: CGGlyph = 0
        var advance = CGSize.zero
        let spaceChar: [UniChar] = [0x0020] // space character
        CTFontGetGlyphsForCharacters(defaultFont, spaceChar, &glyph, 1)
        CTFontGetAdvancesForGlyphs(defaultFont, .default, &glyph, &advance, 1)
        return advance.width
    }

    /// Metrics for the default font.
    public var fontMetrics: (ascent: CGFloat, descent: CGFloat, leading: CGFloat) {
        (
            CTFontGetAscent(defaultFont),
            CTFontGetDescent(defaultFont),
            CTFontGetLeading(defaultFont)
        )
    }

    /// Full line height for the default font.
    public var lineHeight: CGFloat {
        let m = fontMetrics
        return ceil(m.ascent + m.descent + m.leading)
    }
}
