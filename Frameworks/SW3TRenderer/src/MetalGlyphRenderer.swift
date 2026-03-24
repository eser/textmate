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
import os.log
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
        var origin = CGPoint(x: -boundingRect.origin.x + 1, y: -boundingRect.origin.y + 1)
        CTFontDrawGlyphs(font, &glyphRef, &origin, 1, ctx)

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
            // Preserve destination alpha — glyph quads with atlas alpha=0 must not
            // punch holes in the texture's alpha channel (causes visible backgrounds)
            glyphDesc.colorAttachments[0].sourceAlphaBlendFactor = .zero
            glyphDesc.colorAttachments[0].destinationAlphaBlendFactor = .one
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
        backgroundColor: NSColor,
        backingScale: CGFloat = 2.0
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

        for (attrText, origin, _) in lines {
            let line = CTLineCreateWithAttributedString(attrText)
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]

            for run in runs {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)

                let attrs = CTRunGetAttributes(run) as! [CFString: Any]
                let baseFont = (attrs[kCTFontAttributeName] as! CTFont?) ?? CTFontCreateWithName("Menlo" as CFString, 13, nil)
                // Scale font for Retina: rasterize at pixel size, not point size
                let scaledSize = CTFontGetSize(baseFont) * backingScale
                let font = CTFontCreateCopyWithAttributes(baseFont, scaledSize, nil, nil)

                // Extract foreground color from CTRun (kCTForegroundColorAttributeName = CGColor)
                let color: SIMD4<Float>
                if let colorVal = attrs[kCTForegroundColorAttributeName] {
                    let cg = unsafeBitCast(colorVal as AnyObject, to: CGColor.self)
                    if let comps = cg.components, comps.count >= 3 {
                        color = SIMD4(Float(comps[0]), Float(comps[1]), Float(comps[2]),
                                     comps.count >= 4 ? Float(comps[3]) : 1)
                    } else {
                        color = SIMD4(1, 1, 1, 1)
                    }
                } else {
                    color = SIMD4(1, 1, 1, 1)
                }

                let s = Float(backingScale)
                for i in 0..<count {
                    guard let entry = atlas.entry(for: glyphs[i], font: font) else { continue }
                    let uv = atlas.uvRect(for: entry)

                    // positions are in points, scale to pixels
                    let x = Float(origin.x) + Float(positions[i].x) * s + entry.bearingX
                    let y = Float(origin.y) + Float(positions[i].y) * s - entry.bearingY - Float(entry.height)
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
            let byteLen = vertices.count * MemoryLayout<GlyphVertex>.stride
            // setVertexBytes has a 4KB limit; use a buffer for larger data
            if byteLen <= 4096 {
                encoder.setVertexBytes(vertices, length: byteLen, index: 0)
            } else {
                guard let buf = device.makeBuffer(bytes: vertices, length: byteLen, options: .storageModeShared) else {
                    encoder.endEncoding()
                    cmdBuf.commit()
                    return
                }
                encoder.setVertexBuffer(buf, offset: 0, index: 0)
            }
            encoder.setVertexBytes(&vp, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
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

    // MARK: - Pipeline Integration (Step 4)

    /// Cached offscreen texture for pipeline rendering.
    private var offscreenTexture: MTLTexture?
    private var offscreenWidth: Int = 0
    private var offscreenHeight: Int = 0

    /// Cache CGImage → Metal texture uploads (keyed by CGImage pointer).
    private var imageTextureCache: [UnsafeRawPointer: MTLTexture] = [:]

    /// Upload a CGImage to a Metal texture (cached).
    private func getImageTexture(for cgImage: CGImage) -> MTLTexture? {
        let key = UnsafeRawPointer(Unmanaged.passUnretained(cgImage as AnyObject).toOpaque())
        if let cached = imageTextureCache[key] { return cached }

        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return nil }

        // Render CGImage into a grayscale bitmap (same format as glyph atlas: r8Unorm)
        let bytesPerRow = w
        var bitmap = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &bitmap, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        bitmap.withUnsafeBufferPointer { ptr in
            tex.replace(region: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: w, height: h, depth: 1)),
                       mipmapLevel: 0, withBytes: ptr.baseAddress!, bytesPerRow: bytesPerRow)
        }

        imageTextureCache[key] = tex
        return tex
    }

    private func getOffscreenTexture(width: Int, height: Int) -> MTLTexture? {
        if let tex = offscreenTexture, offscreenWidth == width, offscreenHeight == height {
            return tex
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = device.hasUnifiedMemory ? .shared : .managed
        offscreenTexture = device.makeTexture(descriptor: desc)
        offscreenWidth = width
        offscreenHeight = height
        return offscreenTexture
    }

    /// Render collected pipeline commands (from dual-mode context_t) and draw into the current CGContext.
    ///
    /// Called from OakTextView.drawRect via performSelector. The data dictionary contains:
    ///   - "rects": [[String: NSNumber]] — fill rects with RGBA colors (from metal_rect_cmd_t)
    ///   - "lines": [NSDictionary] — text lines with CTLineRef (from metal_line_cmd_t)
    ///   - "viewportW/H": pixel dimensions of the render target
    ///   - "scale": backing scale factor
    ///   - "visibleX/Y": origin of the visible rect in view coordinates
    ///   - "drawWidth/Height": size of the draw rect in points
    @objc func renderPipelineData(_ data: NSDictionary) {
        guard let rectArray = data["rects"] as? [[String: NSNumber]],
              let lineArray = data["lines"] as? [NSDictionary],
              let viewportW = (data["viewportW"] as? NSNumber)?.intValue,
              let viewportH = (data["viewportH"] as? NSNumber)?.intValue,
              let scale = (data["scale"] as? NSNumber)?.doubleValue,
              let visX = (data["visibleX"] as? NSNumber)?.doubleValue,
              let visY = (data["visibleY"] as? NSNumber)?.doubleValue,
              let drawW = (data["drawWidth"] as? NSNumber)?.doubleValue,
              let drawH = (data["drawHeight"] as? NSNumber)?.doubleValue,
              let glyphPipeline, let rectPipeline, let atlas
        else { return }

        let texW = max(1, viewportW)
        let texH = max(1, viewportH)
        guard let texture = getOffscreenTexture(width: texW, height: texH) else { return }

        // Create render pass — clear with background color from first rect fill
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = texture
        renderPass.colorAttachments[0].loadAction = .clear
        if let bgRect = rectArray.first {
            renderPass.colorAttachments[0].clearColor = MTLClearColor(
                red: bgRect["r"]!.doubleValue, green: bgRect["g"]!.doubleValue,
                blue: bgRect["b"]!.doubleValue, alpha: 1.0)
        } else {
            renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        }
        renderPass.colorAttachments[0].storeAction = .store

        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: renderPass) else { return }

        var vp = SIMD2<Float>(Float(texW), Float(texH))
        let s = Float(scale)
        let offsetX = Float(visX)
        let offsetY = Float(visY)

        // 1. Render rect fills (skip first — it's the background, handled by clear color)
        if rectArray.count > 1 {
            encoder.setRenderPipelineState(rectPipeline)
            var rects: [SIMD4<Float>] = []
            var colors: [SIMD4<Float>] = []

            for i in 1..<rectArray.count {
                let dict = rectArray[i]
                let x = (dict["x"]!.floatValue - offsetX) * s
                let y = (dict["y"]!.floatValue - offsetY) * s
                let w = dict["w"]!.floatValue * s
                let h = dict["h"]!.floatValue * s
                rects.append(SIMD4(x, y, w, h))
                colors.append(SIMD4(dict["r"]!.floatValue, dict["g"]!.floatValue,
                                    dict["b"]!.floatValue, dict["a"]!.floatValue))
            }

            if !rects.isEmpty {
                let rectBytes = rects.count * MemoryLayout<SIMD4<Float>>.stride
                let colorBytes = colors.count * MemoryLayout<SIMD4<Float>>.stride
                if rectBytes <= 4096 {
                    encoder.setVertexBytes(rects, length: rectBytes, index: 0)
                } else {
                    guard let buf = device.makeBuffer(bytes: rects, length: rectBytes, options: .storageModeShared) else {
                        encoder.endEncoding(); cmdBuf.commit(); return
                    }
                    encoder.setVertexBuffer(buf, offset: 0, index: 0)
                }
                if colorBytes <= 4096 {
                    encoder.setVertexBytes(colors, length: colorBytes, index: 1)
                } else {
                    guard let buf = device.makeBuffer(bytes: colors, length: colorBytes, options: .storageModeShared) else {
                        encoder.endEncoding(); cmdBuf.commit(); return
                    }
                    encoder.setVertexBuffer(buf, offset: 0, index: 1)
                }
                encoder.setVertexBytes(&vp, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: rects.count * 6)
            }
        }

        // 2. Render text glyphs from collected CTLineRef commands
        encoder.setRenderPipelineState(glyphPipeline)
        var vertices: [GlyphVertex] = []
        for lineDict in lineArray {
            guard let lineObj = lineDict["line"] else { continue }
            let ctLine = lineObj as! CTLine
            let lx = ((lineDict["x"] as? NSNumber)?.floatValue ?? 0)
            let ly = ((lineDict["y"] as? NSNumber)?.floatValue ?? 0)
            let height = ((lineDict["height"] as? NSNumber)?.floatValue ?? 0)

            let runs = CTLineGetGlyphRuns(ctLine) as! [CTRun]

            for run in runs {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)

                let attrs = CTRunGetAttributes(run) as! [CFString: Any]
                let baseFont: CTFont
                if let fontVal = attrs[kCTFontAttributeName] {
                    baseFont = (fontVal as! CTFont)
                } else {
                    baseFont = CTFontCreateWithName("Menlo" as CFString, 13, nil)
                }
                let scaledSize = CTFontGetSize(baseFont) * CGFloat(scale)
                let font = CTFontCreateCopyWithAttributes(baseFont, scaledSize, nil, nil)

                // Extract foreground color (CGColorRef from kCTForegroundColorAttributeName)
                let color: SIMD4<Float>
                if let colorVal = attrs[kCTForegroundColorAttributeName] {
                    let cg = unsafeBitCast(colorVal as AnyObject, to: CGColor.self)
                    if let comps = cg.components, comps.count >= 3 {
                        color = SIMD4(Float(comps[0]), Float(comps[1]), Float(comps[2]),
                                     comps.count >= 4 ? Float(comps[3]) : 1)
                    } else { color = SIMD4(1, 1, 1, 1) }
                } else { color = SIMD4(1, 1, 1, 1) }

                for i in 0..<count {
                    guard let entry = atlas.entry(for: glyphs[i], font: font) else { continue }
                    let uv = atlas.uvRect(for: entry)

                    // Position: offset from visible rect origin, scale to pixels
                    let gx = (lx - offsetX + Float(positions[i].x)) * s + entry.bearingX
                    // In flipped coords, text position y is baseline from top.
                    // CTRun positions[i].y is relative to text position (usually 0 for horizontal text).
                    let gy = (ly - offsetY + Float(positions[i].y)) * s - entry.bearingY - Float(entry.height) + height * s
                    let gw = Float(entry.width)
                    let gh = Float(entry.height)

                    // Two triangles per glyph quad
                    vertices.append(GlyphVertex(position: SIMD2(gx, gy),       texCoord: SIMD2(uv.u0, uv.v0), color: color))
                    vertices.append(GlyphVertex(position: SIMD2(gx+gw, gy),    texCoord: SIMD2(uv.u1, uv.v0), color: color))
                    vertices.append(GlyphVertex(position: SIMD2(gx, gy+gh),    texCoord: SIMD2(uv.u0, uv.v1), color: color))
                    vertices.append(GlyphVertex(position: SIMD2(gx+gw, gy),    texCoord: SIMD2(uv.u1, uv.v0), color: color))
                    vertices.append(GlyphVertex(position: SIMD2(gx+gw, gy+gh), texCoord: SIMD2(uv.u1, uv.v1), color: color))
                    vertices.append(GlyphVertex(position: SIMD2(gx, gy+gh),    texCoord: SIMD2(uv.u0, uv.v1), color: color))
                }
            }
        }

        if !vertices.isEmpty {
            let byteLen = vertices.count * MemoryLayout<GlyphVertex>.stride
            if byteLen <= 4096 {
                encoder.setVertexBytes(vertices, length: byteLen, index: 0)
            } else {
                guard let buf = device.makeBuffer(bytes: vertices, length: byteLen, options: .storageModeShared) else {
                    encoder.endEncoding(); cmdBuf.commit(); return
                }
                encoder.setVertexBuffer(buf, offset: 0, index: 0)
            }
            encoder.setVertexBytes(&vp, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.setFragmentTexture(atlas.texture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }

        // 3. Render image commands (spelling dots, folding dots)
        if let imageArray = data["images"] as? [NSDictionary], !imageArray.isEmpty {
            encoder.setRenderPipelineState(glyphPipeline)
            var imgVertices: [GlyphVertex] = []

            for imgDict in imageArray {
                guard let cgImg = imgDict["image"] else { continue }
                let cgImage = cgImg as! CGImage
                let ix = ((imgDict["x"] as? NSNumber)?.floatValue ?? 0)
                let iy = ((imgDict["y"] as? NSNumber)?.floatValue ?? 0)
                let iw = ((imgDict["w"] as? NSNumber)?.floatValue ?? 0)
                let ih = ((imgDict["h"] as? NSNumber)?.floatValue ?? 0)
                let ir = ((imgDict["r"] as? NSNumber)?.floatValue ?? 1)
                let ig = ((imgDict["g"] as? NSNumber)?.floatValue ?? 1)
                let ib = ((imgDict["b"] as? NSNumber)?.floatValue ?? 1)
                let ia = ((imgDict["a"] as? NSNumber)?.floatValue ?? 1)
                let isMask = ((imgDict["isMask"] as? NSNumber)?.boolValue ?? false)

                // Upload CGImage as a small Metal texture (cached by pointer)
                guard let imgTex = getImageTexture(for: cgImage) else { continue }

                // Flush any pending glyph vertices before switching textures
                if !imgVertices.isEmpty {
                    let byteLen = imgVertices.count * MemoryLayout<GlyphVertex>.stride
                    if byteLen <= 4096 {
                        encoder.setVertexBytes(imgVertices, length: byteLen, index: 0)
                    } else {
                        guard let buf = device.makeBuffer(bytes: imgVertices, length: byteLen, options: .storageModeShared) else { continue }
                        encoder.setVertexBuffer(buf, offset: 0, index: 0)
                    }
                    encoder.setVertexBytes(&vp, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
                    encoder.setFragmentTexture(imgTex, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: imgVertices.count)
                    imgVertices.removeAll()
                }

                let color = isMask ? SIMD4<Float>(ir, ig, ib, ia) : SIMD4<Float>(1, 1, 1, 1)
                let px = (ix - offsetX) * s
                let py = (iy - offsetY) * s
                let pw = iw * s
                let ph = ih * s

                // Image quad — full UV coverage of the image texture
                imgVertices.append(GlyphVertex(position: SIMD2(px, py),       texCoord: SIMD2(0, 0), color: color))
                imgVertices.append(GlyphVertex(position: SIMD2(px+pw, py),    texCoord: SIMD2(1, 0), color: color))
                imgVertices.append(GlyphVertex(position: SIMD2(px, py+ph),    texCoord: SIMD2(0, 1), color: color))
                imgVertices.append(GlyphVertex(position: SIMD2(px+pw, py),    texCoord: SIMD2(1, 0), color: color))
                imgVertices.append(GlyphVertex(position: SIMD2(px+pw, py+ph), texCoord: SIMD2(1, 1), color: color))
                imgVertices.append(GlyphVertex(position: SIMD2(px, py+ph),    texCoord: SIMD2(0, 1), color: color))

                // Flush this image's vertices with its texture
                let byteLen = imgVertices.count * MemoryLayout<GlyphVertex>.stride
                if byteLen <= 4096 {
                    encoder.setVertexBytes(imgVertices, length: byteLen, index: 0)
                } else if let buf = device.makeBuffer(bytes: imgVertices, length: byteLen, options: .storageModeShared) {
                    encoder.setVertexBuffer(buf, offset: 0, index: 0)
                }
                encoder.setVertexBytes(&vp, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
                encoder.setFragmentTexture(imgTex, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: imgVertices.count)
                imgVertices.removeAll()
            }
        }

        encoder.endEncoding()

        // For managed storage (Intel Mac), synchronize texture for CPU readback
        if !device.hasUnifiedMemory {
            if let blit = cmdBuf.makeBlitCommandEncoder() {
                blit.synchronize(resource: texture)
                blit.endEncoding()
            }
        }

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        // 3. Read texture back and draw into current CGContext.
        // Use Data (reference-counted) so the pixel buffer stays alive until
        // CoreGraphics finishes reading — CG uses display lists and may read
        // asynchronously after cgContext.draw() returns.
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }

        let bytesPerRow = texW * 4
        let totalBytes = bytesPerRow * texH
        var pixelData = Data(count: totalBytes)
        pixelData.withUnsafeMutableBytes { ptr in
            texture.getBytes(ptr.baseAddress!, bytesPerRow: bytesPerRow,
                             from: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: texW, height: texH, depth: 1)),
                             mipmapLevel: 0)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: pixelData as CFData),
              let image = CGImage(width: texW, height: texH,
                                 bitsPerComponent: 8, bitsPerPixel: 32,
                                 bytesPerRow: bytesPerRow, space: colorSpace,
                                 bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                                 provider: provider, decode: nil,
                                 shouldInterpolate: false, intent: .defaultIntent)
        else { return }

        // CGContextDrawImage always places image row 0 at the BOTTOM of destRect,
        // ignoring the context's flipped state. In OakTextView's flipped context
        // (y=0 at top), this causes the image to render upside-down.
        // Fix: apply a local y-flip transform so the image draws correctly.
        cgContext.saveGState()
        cgContext.translateBy(x: 0, y: CGFloat(visY) + CGFloat(drawH))
        cgContext.scaleBy(x: 1, y: -1)
        cgContext.draw(image, in: CGRect(x: visX, y: 0, width: drawW, height: drawH))
        cgContext.restoreGState()
    }
}
