// SW³ TextFellow — Text Renderer
// SPDX-License-Identifier: GPL-3.0-or-later

import Metal
import MetalKit
import CoreGraphics
import CoreText
import SW3TViewport
import SW3TSyntax

/// GPU vertex for glyph quads — matches `GlyphVertex` in Shaders.metal.
public struct GlyphVertex {
    var position: SIMD2<Float>
    var texCoord: SIMD2<Float>
    var color: SIMD4<Float>
}

/// GPU vertex for filled rectangles — matches `RectVertex` in Shaders.metal.
public struct RectVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

/// Projection uniforms — matches `Uniforms` in Shaders.metal.
public struct Uniforms {
    var projectionMatrix: simd_float4x4
}

/// The main text rendering engine.
///
/// ```
///  Frame Pipeline:
///
///  ViewportProvider.visibleContent(in: rect)
///        │
///        ▼
///  [RenderLine]  ──► CoreText shaping (CTLine per line)
///        │
///        ▼
///  For each glyph:
///    GlyphAtlas.region(for: key) ──► cache hit or rasterize+upload
///        │
///        ▼
///  Build vertex buffers:
///    - Rect vertices (selections, caret, backgrounds)
///    - Glyph vertices (textured quads with per-vertex syntax color)
///        │
///        ▼
///  MTLCommandBuffer:
///    1. Draw rects (selections, line backgrounds)
///    2. Draw glyphs (text)
///    3. Draw cursor (animated rect)
///        │
///        ▼
///  Present to CAMetalLayer (MTKView)
/// ```
public final class TextEditorRenderer: NSObject {
    public let context: RenderContext
    private let atlas: GlyphAtlas
    private let glyphPipeline: MTLRenderPipelineState
    private let rectPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var shaper: TextShaper

    /// Current viewport provider — set by the owning view.
    public var viewportProvider: (any ViewportProvider)?

    /// Font name for rendering.
    public var fontName: String = "Menlo" {
        didSet { shaper = TextShaper(fontName: fontName, fontSize: fontSize) }
    }

    /// Font size in points.
    public var fontSize: CGFloat = 13.0 {
        didSet { shaper = TextShaper(fontName: fontName, fontSize: fontSize) }
    }

    /// Line height in points (computed from font metrics).
    public var lineHeight: CGFloat { shaper.lineHeight }

    /// Background color.
    public var backgroundColor: SIMD4<Float> = SIMD4(0.1, 0.1, 0.1, 1.0)

    /// Cursor color.
    public var cursorColor: SIMD4<Float> = SIMD4(1.0, 1.0, 1.0, 1.0)

    /// Cursor animation phase (0..1, driven by display link).
    public var cursorPhase: Float = 1.0

    public init?(context: RenderContext) {
        self.context = context
        self.atlas = GlyphAtlas(device: context.device)
        self.shaper = TextShaper(fontName: "Menlo", fontSize: 13.0)

        // Create glyph render pipeline
        guard let glyphVert = context.library.makeFunction(name: "glyph_vertex"),
              let glyphFrag = context.library.makeFunction(name: "glyph_fragment")
        else { return nil }

        let glyphDesc = MTLRenderPipelineDescriptor()
        glyphDesc.vertexFunction = glyphVert
        glyphDesc.fragmentFunction = glyphFrag
        glyphDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        glyphDesc.colorAttachments[0].isBlendingEnabled = true
        glyphDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        glyphDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        glyphDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        glyphDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let glyphPipeline = try? context.device.makeRenderPipelineState(descriptor: glyphDesc)
        else { return nil }

        // Create rect render pipeline
        guard let rectVert = context.library.makeFunction(name: "rect_vertex"),
              let rectFrag = context.library.makeFunction(name: "rect_fragment")
        else { return nil }

        let rectDesc = MTLRenderPipelineDescriptor()
        rectDesc.vertexFunction = rectVert
        rectDesc.fragmentFunction = rectFrag
        rectDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        rectDesc.colorAttachments[0].isBlendingEnabled = true
        rectDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        rectDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha

        guard let rectPipeline = try? context.device.makeRenderPipelineState(descriptor: rectDesc)
        else { return nil }

        // Create sampler for glyph atlas
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .notMipmapped
        guard let sampler = context.device.makeSamplerState(descriptor: samplerDesc)
        else { return nil }

        self.glyphPipeline = glyphPipeline
        self.rectPipeline = rectPipeline
        self.sampler = sampler
        super.init()
    }

    /// Build an orthographic projection matrix for the given viewport.
    public static func orthographicProjection(width: Float, height: Float) -> simd_float4x4 {
        // Maps (0,0)-(width,height) to Metal clip space (-1,-1)-(1,1)
        let sx: Float = 2.0 / width
        let sy: Float = -2.0 / height  // Flip Y (Metal Y is up, we want Y down)
        return simd_float4x4(columns: (
            SIMD4(sx,   0,    0, 0),
            SIMD4(0,    sy,   0, 0),
            SIMD4(0,    0,    1, 0),
            SIMD4(-1,   1,    0, 1)
        ))
    }
}

// MARK: - MTKViewDelegate

extension TextEditorRenderer: MTKViewDelegate {
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Viewport resize — no action needed, projection recalculated per frame
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = context.commandQueue.makeCommandBuffer()
        else { return }

        // Set clear color
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(backgroundColor.x),
            green: Double(backgroundColor.y),
            blue: Double(backgroundColor.z),
            alpha: Double(backgroundColor.w)
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else { return }

        let width = Float(view.drawableSize.width)
        let height = Float(view.drawableSize.height)
        var uniforms = Uniforms(
            projectionMatrix: Self.orthographicProjection(width: width, height: height)
        )

        // Get visible content from viewport provider
        let scale = Float(view.window?.backingScaleFactor ?? 2.0)
        let visibleRect = CGRect(
            x: 0, y: 0,
            width: CGFloat(width) / CGFloat(scale),
            height: CGFloat(height) / CGFloat(scale)
        )

        if let viewport = viewportProvider {
            let lines = viewport.visibleContent(in: visibleRect)
            let cursors = viewport.cursorPositions()

            // 1. Draw selection backgrounds (rect pipeline)
            drawSelections(lines: lines, encoder: encoder, uniforms: &uniforms, scale: scale)

            // 2. Draw text glyphs (glyph pipeline)
            drawGlyphs(lines: lines, encoder: encoder, uniforms: &uniforms, scale: scale)

            // 3. Draw cursors (rect pipeline, animated)
            drawCursors(cursors: cursors, encoder: encoder, uniforms: &uniforms, scale: scale)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func drawSelections(
        lines: [RenderLine],
        encoder: MTLRenderCommandEncoder,
        uniforms: inout Uniforms,
        scale: Float
    ) {
        var vertices: [RectVertex] = []
        let lh = Float(shaper.lineHeight) * scale
        let colWidth = Float(shaper.columnWidth) * scale
        let gutterOffset: Float = 50.0 * scale // gutter width in pixels
        let selectionColor = SIMD4<Float>(0.25, 0.45, 0.75, 0.35) // TextMate-style blue selection

        for line in lines {
            let lineY = Float(line.lineNumber) * lh

            for selection in line.selections {
                let x0 = gutterOffset + Float(selection.lowerBound) * colWidth
                let x1 = gutterOffset + Float(selection.upperBound) * colWidth
                let y0 = lineY
                let y1 = lineY + lh

                // Two triangles for the selection rectangle
                vertices.append(RectVertex(position: SIMD2(x0, y0), color: selectionColor))
                vertices.append(RectVertex(position: SIMD2(x1, y0), color: selectionColor))
                vertices.append(RectVertex(position: SIMD2(x1, y1), color: selectionColor))
                vertices.append(RectVertex(position: SIMD2(x0, y0), color: selectionColor))
                vertices.append(RectVertex(position: SIMD2(x1, y1), color: selectionColor))
                vertices.append(RectVertex(position: SIMD2(x0, y1), color: selectionColor))
            }
        }

        guard !vertices.isEmpty else { return }

        encoder.setRenderPipelineState(rectPipeline)
        encoder.setVertexBytes(vertices, length: MemoryLayout<RectVertex>.stride * vertices.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    /// The core rendering pipeline:
    ///
    /// ```
    ///  RenderLine.text ──► TextShaper.shapeLine()
    ///       │
    ///       ▼
    ///  [ShapedGlyph] ──► GlyphAtlas.region(for: key)
    ///       │                    │
    ///       │              cache hit? ──► UV rect
    ///       │              cache miss? ──► rasterize, upload, UV rect
    ///       │
    ///       ▼
    ///  Build GlyphVertex[] (position + UV + color)
    ///       │
    ///       ▼
    ///  MTLRenderCommandEncoder.drawPrimitives()
    /// ```
    private func drawGlyphs(
        lines: [RenderLine],
        encoder: MTLRenderCommandEncoder,
        uniforms: inout Uniforms,
        scale: Float
    ) {
        var vertices: [GlyphVertex] = []
        vertices.reserveCapacity(lines.count * 80 * 6) // ~80 glyphs/line, 6 vertices/glyph

        let lh = Float(shaper.lineHeight) * scale
        let gutterOffset: Float = 50.0 * scale
        let defaultColor = SIMD4<Float>(0.92, 0.92, 0.92, 1.0) // Default text color (light gray on dark)

        for line in lines {
            guard !line.text.isEmpty else { continue }

            // Shape the line with CoreText
            let shaped = shaper.shapeLine(line.text)

            // Baseline Y: top of line + ascent
            let lineTop = Float(line.lineNumber) * lh
            let baseline = lineTop + Float(shaped.ascent) * scale

            // Build glyph quads
            for glyph in shaped.glyphs {
                // Look up or rasterize the glyph in the atlas
                let atlasKey = GlyphAtlas.GlyphKey(
                    glyphID: glyph.glyphID,
                    fontName: glyph.fontName,
                    fontSize: glyph.fontSize,
                    scale: CGFloat(scale)
                )

                guard let region = atlas.region(for: atlasKey) else { continue }

                // Determine syntax color for this glyph position
                let glyphColor = colorForGlyph(
                    at: glyph.position.x,
                    tokens: line.tokens,
                    defaultColor: defaultColor
                )

                // Glyph quad position (in pixels, screen coordinates)
                let x = gutterOffset + Float(glyph.position.x) * scale + Float(region.bearing.x) * scale
                let y = baseline - Float(region.bearing.y) * scale - Float(region.pixelSize.height)
                let w = Float(region.pixelSize.width)
                let h = Float(region.pixelSize.height)

                // UV coordinates in the atlas texture
                let u0 = Float(region.uvRect.minX)
                let v0 = Float(region.uvRect.minY)
                let u1 = Float(region.uvRect.maxX)
                let v1 = Float(region.uvRect.maxY)

                // Two triangles for the glyph quad
                vertices.append(GlyphVertex(position: SIMD2(x, y),     texCoord: SIMD2(u0, v0), color: glyphColor))
                vertices.append(GlyphVertex(position: SIMD2(x + w, y), texCoord: SIMD2(u1, v0), color: glyphColor))
                vertices.append(GlyphVertex(position: SIMD2(x + w, y + h), texCoord: SIMD2(u1, v1), color: glyphColor))
                vertices.append(GlyphVertex(position: SIMD2(x, y),     texCoord: SIMD2(u0, v0), color: glyphColor))
                vertices.append(GlyphVertex(position: SIMD2(x + w, y + h), texCoord: SIMD2(u1, v1), color: glyphColor))
                vertices.append(GlyphVertex(position: SIMD2(x, y + h), texCoord: SIMD2(u0, v1), color: glyphColor))
            }
        }

        guard !vertices.isEmpty, atlas.pageCount > 0 else { return }

        // Bind glyph pipeline and atlas texture
        encoder.setRenderPipelineState(glyphPipeline)
        encoder.setVertexBytes(vertices, length: MemoryLayout<GlyphVertex>.stride * vertices.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        // Note: atlas texture binding would go here:
        // encoder.setFragmentTexture(atlas.pages[0].texture, index: 0)
        // encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    /// Map a glyph's x position to a syntax color from the token list.
    ///
    /// Tokens have byte ranges; we approximate by comparing x positions.
    /// For production, this should use character-to-token index mapping.
    private func colorForGlyph(
        at xPosition: CGFloat,
        tokens: [HighlightToken],
        defaultColor: SIMD4<Float>
    ) -> SIMD4<Float> {
        // Simple scope → color mapping (will be replaced by ThemeResolver)
        for token in tokens {
            let scope = token.scope
            if scope.contains("keyword") { return SIMD4(0.78, 0.45, 0.82, 1.0) } // purple
            if scope.contains("string") { return SIMD4(0.60, 0.80, 0.40, 1.0) }  // green
            if scope.contains("comment") { return SIMD4(0.50, 0.50, 0.50, 1.0) }  // gray
            if scope.contains("number") { return SIMD4(0.82, 0.60, 0.40, 1.0) }   // orange
            if scope.contains("type") { return SIMD4(0.40, 0.70, 0.85, 1.0) }     // blue
            if scope.contains("function") { return SIMD4(0.40, 0.85, 0.70, 1.0) } // teal
            if scope.contains("variable") { return SIMD4(0.92, 0.85, 0.65, 1.0) } // yellow
        }
        return defaultColor
    }

    private func drawCursors(
        cursors: [CGPoint],
        encoder: MTLRenderCommandEncoder,
        uniforms: inout Uniforms,
        scale: Float
    ) {
        guard !cursors.isEmpty else { return }

        var vertices: [RectVertex] = []
        let cursorWidth: Float = 2.0 * scale
        let cursorHeight = Float(lineHeight) * scale
        let animatedAlpha = cursorPhase // 0..1, driven by display link

        for cursor in cursors {
            let x = Float(cursor.x) * scale
            let y = Float(cursor.y) * scale
            let color = SIMD4<Float>(cursorColor.x, cursorColor.y, cursorColor.z, animatedAlpha)

            // Two triangles for the cursor rectangle
            vertices.append(RectVertex(position: SIMD2(x, y), color: color))
            vertices.append(RectVertex(position: SIMD2(x + cursorWidth, y), color: color))
            vertices.append(RectVertex(position: SIMD2(x + cursorWidth, y + cursorHeight), color: color))
            vertices.append(RectVertex(position: SIMD2(x, y), color: color))
            vertices.append(RectVertex(position: SIMD2(x + cursorWidth, y + cursorHeight), color: color))
            vertices.append(RectVertex(position: SIMD2(x, y + cursorHeight), color: color))
        }

        guard !vertices.isEmpty else { return }

        encoder.setRenderPipelineState(rectPipeline)
        encoder.setVertexBytes(vertices, length: MemoryLayout<RectVertex>.stride * vertices.count, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }
}
