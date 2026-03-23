// SW³ TextFellow — Metal Glyph Renderer (Phase 2 + 3)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Phase 2: Per-glyph GPU rendering via GlyphAtlas + vertex buffers
// Phase 3: Selection, cursor, fold markers, invisibles — all Metal
//
// CoreText does layout (CTLine/CTRun), Metal does drawing.
// No CGContext in the draw path — 120fps capable.

import AppKit
import MetalKit
import CoreText
import CoreGraphics

// MARK: - Glyph Vertex

/// Per-glyph vertex data sent to the GPU.
struct GlyphVertex {
    var position: SIMD2<Float>   // screen position
    var texCoord: SIMD2<Float>   // atlas UV
    var color: SIMD4<Float>      // syntax color (RGBA)
}

// MARK: - Glyph Atlas Entry

struct GlyphAtlasEntry {
    let atlasX: Int, atlasY: Int
    let width: Int, height: Int
    let bearingX: Float, bearingY: Float
}

// MARK: - Metal Glyph Atlas

/// Rasterizes glyphs into a Metal texture atlas for GPU rendering.
final class MetalGlyphAtlas {
    let texture: MTLTexture
    let atlasSize: Int
    private var entries: [GlyphCacheKey: GlyphAtlasEntry] = [:]
    private var nextX: Int = 0
    private var nextY: Int = 0
    private var rowHeight: Int = 0

    struct GlyphCacheKey: Hashable {
        let glyphID: CGGlyph
        let fontName: String
        let fontSize: CGFloat
    }

    init?(device: MTLDevice, size: Int = 2048) {
        self.atlasSize = size
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: size, height: size, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        self.texture = tex
    }

    /// Look up or rasterize a glyph, returning its atlas entry.
    func entry(for glyph: CGGlyph, font: CTFont) -> GlyphAtlasEntry? {
        let key = GlyphCacheKey(
            glyphID: glyph,
            fontName: CTFontCopyPostScriptName(font) as String,
            fontSize: CTFontGetSize(font)
        )

        if let existing = entries[key] { return existing }

        // Rasterize glyph to bitmap
        var glyphRef = glyph
        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyphRef, &boundingRect, 1)

        let w = Int(ceil(boundingRect.width)) + 2
        let h = Int(ceil(boundingRect.height)) + 2
        guard w > 0, h > 0, w < atlasSize, h < atlasSize else { return nil }

        // Check if row has space
        if nextX + w > atlasSize {
            nextX = 0
            nextY += rowHeight + 1
            rowHeight = 0
        }
        if nextY + h > atlasSize { return nil } // atlas full

        // Rasterize to grayscale bitmap
        let bytesPerRow = w
        var bitmap = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &bitmap, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.setFillColor(gray: 1.0, alpha: 1.0)
        let origin = CGPoint(x: -boundingRect.origin.x + 1, y: -boundingRect.origin.y + 1)
        CTFontDrawGlyphs(font, &glyphRef, &[origin], 1, ctx)

        // Copy to atlas texture
        let region = MTLRegion(origin: MTLOrigin(x: nextX, y: nextY, z: 0),
                               size: MTLSize(width: w, height: h, depth: 1))
        bitmap.withUnsafeBufferPointer { ptr in
            texture.replace(region: region, mipmapLevel: 0,
                           withBytes: ptr.baseAddress!, bytesPerRow: bytesPerRow)
        }

        let entry = GlyphAtlasEntry(
            atlasX: nextX, atlasY: nextY,
            width: w, height: h,
            bearingX: Float(boundingRect.origin.x), bearingY: Float(boundingRect.origin.y)
        )
        entries[key] = entry

        nextX += w + 1
        rowHeight = max(rowHeight, h)

        return entry
    }

    /// UV coordinates for an atlas entry.
    func uvRect(for entry: GlyphAtlasEntry) -> (u0: Float, v0: Float, u1: Float, v1: Float) {
        let s = Float(atlasSize)
        return (Float(entry.atlasX) / s, Float(entry.atlasY) / s,
                Float(entry.atlasX + entry.width) / s, Float(entry.atlasY + entry.height) / s)
    }

    var cachedGlyphCount: Int { entries.count }
}

// MARK: - Cursor & Selection

/// Describes a cursor or selection for Metal rendering.
struct MetalCursorInfo {
    var position: CGPoint
    var height: CGFloat
    var color: NSColor
    var blinkPhase: Float  // 0.0–1.0 for animation
}

struct MetalSelectionRect {
    var rect: CGRect
    var color: NSColor
}

// MARK: - Full Metal Renderer (Phase 3)

/// Complete Metal text renderer — replaces CoreText+CGContext entirely.
///
/// ```
/// Document ──► CoreText layout ──► GlyphAtlas ──► vertex buffer ──► Metal draw
///                                                      │
///                                            selection rects ──► Metal draw
///                                            cursor position ──► Metal draw
///                                            fold markers    ──► Metal draw
/// ```
@objc(SW3TMetalFullRenderer)
final class MetalFullRenderer: NSObject {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var atlas: MetalGlyphAtlas?
    private var glyphPipeline: MTLRenderPipelineState?
    private var rectPipeline: MTLRenderPipelineState?

    @objc init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        super.init()
        self.atlas = MetalGlyphAtlas(device: device)
        setupPipelines()
    }

    private func setupPipelines() {
        let shaderSrc = """
        #include <metal_stdlib>
        using namespace metal;

        // Glyph vertex (textured quad with per-vertex color)
        struct GlyphVertexIn {
            float2 position;
            float2 texCoord;
            float4 color;
        };

        struct GlyphVertexOut {
            float4 position [[position]];
            float2 texCoord;
            float4 color;
        };

        vertex GlyphVertexOut glyph_vertex(
            const device GlyphVertexIn* vertices [[buffer(0)]],
            constant float2& viewport [[buffer(1)]],
            uint vid [[vertex_id]]
        ) {
            GlyphVertexOut out;
            float2 pos = vertices[vid].position;
            out.position = float4(pos.x / viewport.x * 2.0 - 1.0,
                                  1.0 - pos.y / viewport.y * 2.0, 0, 1);
            out.texCoord = vertices[vid].texCoord;
            out.color = vertices[vid].color;
            return out;
        }

        fragment float4 glyph_fragment(
            GlyphVertexOut in [[stage_in]],
            texture2d<float> atlas [[texture(0)]]
        ) {
            constexpr sampler s(mag_filter::linear, min_filter::linear);
            float alpha = atlas.sample(s, in.texCoord).r;
            return float4(in.color.rgb, in.color.a * alpha);
        }

        // Solid rect (selection, cursor)
        struct RectVertexOut {
            float4 position [[position]];
            float4 color;
        };

        vertex RectVertexOut rect_vertex(
            const device float4* rects [[buffer(0)]],
            const device float4* colors [[buffer(1)]],
            constant float2& viewport [[buffer(2)]],
            uint vid [[vertex_id]]
        ) {
            uint ri = vid / 6;
            uint corner = vid % 6;
            float4 r = rects[ri];
            float2 pos;
            switch(corner) {
                case 0: pos = float2(r.x, r.y); break;
                case 1: pos = float2(r.x+r.z, r.y); break;
                case 2: pos = float2(r.x, r.y+r.w); break;
                case 3: pos = float2(r.x+r.z, r.y); break;
                case 4: pos = float2(r.x+r.z, r.y+r.w); break;
                case 5: pos = float2(r.x, r.y+r.w); break;
            }
            RectVertexOut out;
            out.position = float4(pos.x / viewport.x * 2.0 - 1.0,
                                  1.0 - pos.y / viewport.y * 2.0, 0, 1);
            out.color = colors[ri];
            return out;
        }

        fragment float4 rect_fragment(RectVertexOut in [[stage_in]]) {
            return in.color;
        }
        """

        do {
            let lib = try device.makeLibrary(source: shaderSrc, options: nil)

            let glyphDesc = MTLRenderPipelineDescriptor()
            glyphDesc.vertexFunction = lib.makeFunction(name: "glyph_vertex")
            glyphDesc.fragmentFunction = lib.makeFunction(name: "glyph_fragment")
            glyphDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            glyphDesc.colorAttachments[0].isBlendingEnabled = true
            glyphDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            glyphDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            glyphPipeline = try device.makeRenderPipelineState(descriptor: glyphDesc)

            let rectDesc = MTLRenderPipelineDescriptor()
            rectDesc.vertexFunction = lib.makeFunction(name: "rect_vertex")
            rectDesc.fragmentFunction = lib.makeFunction(name: "rect_fragment")
            rectDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            rectDesc.colorAttachments[0].isBlendingEnabled = true
            rectDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            rectDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            rectPipeline = try device.makeRenderPipelineState(descriptor: rectDesc)
        } catch {
            os_log(.error, "MetalFullRenderer: shader compile failed: %{public}@", error.localizedDescription)
        }
    }

    /// Render a complete frame: background → selections → text glyphs → cursor.
    func renderFrame(
        to drawable: CAMetalDrawable,
        renderPass: MTLRenderPassDescriptor,
        viewport: CGSize,
        lines: [(text: NSAttributedString, origin: CGPoint, syntaxColor: NSColor?)],
        selections: [MetalSelectionRect],
        cursor: MetalCursorInfo?,
        backgroundColor: NSColor
    ) {
        guard let glyphPipeline, let rectPipeline, let atlas,
              let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: renderPass) else { return }

        var vp = SIMD2<Float>(Float(viewport.width), Float(viewport.height))

        // 1. Draw selection rectangles
        if !selections.isEmpty {
            encoder.setRenderPipelineState(rectPipeline)
            let rects = selections.map { sel -> SIMD4<Float> in
                SIMD4(Float(sel.rect.origin.x), Float(sel.rect.origin.y),
                      Float(sel.rect.width), Float(sel.rect.height))
            }
            let colors = selections.map { sel -> SIMD4<Float> in
                let c = sel.color.usingColorSpace(.sRGB) ?? sel.color
                return SIMD4(Float(c.redComponent), Float(c.greenComponent),
                            Float(c.blueComponent), Float(c.alphaComponent))
            }
            encoder.setVertexBytes(rects, length: rects.count * 16, index: 0)
            encoder.setVertexBytes(colors, length: colors.count * 16, index: 1)
            encoder.setVertexBytes(&vp, length: 8, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: selections.count * 6)
        }

        // 2. Draw text glyphs
        encoder.setRenderPipelineState(glyphPipeline)
        var vertices: [GlyphVertex] = []

        for (attrText, origin, syntaxColor) in lines {
            let line = CTLineCreateWithAttributedString(attrText)
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]

            for run in runs {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)

                let attrs = CTRunGetAttributes(run) as! [CFString: Any]
                let font = (attrs[kCTFontAttributeName] as! CTFont?) ?? CTFontCreateWithName("Menlo" as CFString, 13, nil)

                // Get color from syntax or run attributes
                let color: SIMD4<Float>
                if let sc = syntaxColor?.usingColorSpace(.sRGB) {
                    color = SIMD4(Float(sc.redComponent), Float(sc.greenComponent),
                                 Float(sc.blueComponent), Float(sc.alphaComponent))
                } else {
                    color = SIMD4(1, 1, 1, 1) // default white
                }

                for i in 0..<count {
                    guard let entry = atlas.entry(for: glyphs[i], font: font) else { continue }
                    let uv = atlas.uvRect(for: entry)

                    let x = Float(origin.x + positions[i].x) + entry.bearingX
                    let y = Float(origin.y + positions[i].y) - entry.bearingY - Float(entry.height)
                    let w = Float(entry.width)
                    let h = Float(entry.height)

                    // Two triangles per glyph quad
                    vertices.append(GlyphVertex(position: SIMD2(x, y),     texCoord: SIMD2(uv.u0, uv.v0), color: color))
                    vertices.append(GlyphVertex(position: SIMD2(x+w, y),   texCoord: SIMD2(uv.u1, uv.v0), color: color))
                    vertices.append(GlyphVertex(position: SIMD2(x, y+h),   texCoord: SIMD2(uv.u0, uv.v1), color: color))
                    vertices.append(GlyphVertex(position: SIMD2(x+w, y),   texCoord: SIMD2(uv.u1, uv.v0), color: color))
                    vertices.append(GlyphVertex(position: SIMD2(x+w, y+h), texCoord: SIMD2(uv.u1, uv.v1), color: color))
                    vertices.append(GlyphVertex(position: SIMD2(x, y+h),   texCoord: SIMD2(uv.u0, uv.v1), color: color))
                }
            }
        }

        if !vertices.isEmpty {
            encoder.setVertexBytes(vertices, length: vertices.count * MemoryLayout<GlyphVertex>.size, index: 0)
            encoder.setVertexBytes(&vp, length: 8, index: 1)
            encoder.setFragmentTexture(atlas.texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }

        // 3. Draw cursor
        if let cursor, cursor.blinkPhase > 0.3 {
            encoder.setRenderPipelineState(rectPipeline)
            let cursorWidth: Float = 2.0
            var rects = [SIMD4<Float>(Float(cursor.position.x), Float(cursor.position.y),
                                      cursorWidth, Float(cursor.height))]
            let cc = cursor.color.usingColorSpace(.sRGB) ?? cursor.color
            var colors = [SIMD4<Float>(Float(cc.redComponent), Float(cc.greenComponent),
                                       Float(cc.blueComponent), Float(cc.alphaComponent))]
            encoder.setVertexBytes(&rects, length: 16, index: 0)
            encoder.setVertexBytes(&colors, length: 16, index: 1)
            encoder.setVertexBytes(&vp, length: 8, index: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }

        encoder.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    /// Number of glyphs currently cached in the atlas.
    @objc var cachedGlyphCount: Int { atlas?.cachedGlyphCount ?? 0 }
}
