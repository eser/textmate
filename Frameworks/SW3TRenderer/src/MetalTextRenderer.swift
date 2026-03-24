import Foundation
import Metal
import MetalKit
import CoreText
import CoreGraphics
import AppKit

// MARK: - Data Types

/// A single line of text to be rendered, carrying its attributed content
/// and pre-parsed syntax token ranges for coloring.
public struct RenderLine: @unchecked Sendable {
    /// Zero-based line number in the document.
    public let lineNumber: Int
    /// Fully attributed text for CoreText shaping.
    public let attributedText: NSAttributedString
    /// Syntax token spans with associated colors, relative to the line start.
    public let tokens: [(range: Range<Int>, color: NSColor)]

    public init(lineNumber: Int,
                attributedText: NSAttributedString,
                tokens: [(range: Range<Int>, color: NSColor)] = []) {
        self.lineNumber = lineNumber
        self.attributedText = attributedText
        self.tokens = tokens
    }
}

// Sendable conformance for the tuple-containing stored property.
// NSAttributedString is not Sendable by default but we accept that for rendering data.

/// Provides the visible line range and content that the renderer should draw.
@MainActor
public protocol ViewportProvider: AnyObject {
    /// The range of line numbers currently visible in the viewport.
    var visibleLineRange: Range<Int> { get }
    /// Return the `RenderLine` for a given line number, or `nil` if unavailable.
    func renderLine(at lineNumber: Int) -> RenderLine?
    /// Total number of lines in the document.
    var totalLineCount: Int { get }
}

// GlyphVertex defined in MetalGlyphRenderer.swift

// MARK: - Metal Text Renderer

/// A Metal-based text renderer that draws syntax-highlighted source code
/// using glyph textures cached in a `GlyphAtlas`.
///
/// Attach this renderer's `view` to your view hierarchy. Set a `viewportProvider`
/// to supply visible lines. The renderer handles frame callbacks via `MTKViewDelegate`.
@MainActor
internal final class MetalTextRenderer: NSObject, @preconcurrency MTKViewDelegate {

    // MARK: Public Properties

    /// The Metal-backed view managed by this renderer.
    public let view: MTKView

    /// Provides visible lines to the renderer each frame.
    public weak var viewportProvider: ViewportProvider?

    /// The glyph atlas shared by this renderer.
    public let glyphAtlas: GlyphAtlas

    /// Line height in points. Defaults to 20.
    public var lineHeight: CGFloat = 20

    /// Left margin for text content in points.
    public var leftMargin: CGFloat = 60

    /// Background color of the view (system-adaptive).
    public var backgroundColor: NSColor = .textBackgroundColor {
        didSet { updateClearColor() }
    }

    // MARK: Metal State

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?

    /// Maximum number of glyphs per frame. Each glyph = 4 vertices, 6 indices.
    private let maxGlyphsPerFrame = 16384
    private var vertices: [GlyphVertex] = []
    private var indices: [UInt32] = []

    // MARK: Init

    /// Create a renderer backed by the given Metal device.
    /// Returns `nil` if the device or command queue cannot be created.
    public init?(device: MTLDevice? = MTLCreateSystemDefaultDevice(),
                 frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)) {
        guard let device else { return nil }
        guard let queue = device.makeCommandQueue() else { return nil }

        self.device = device
        self.commandQueue = queue
        self.glyphAtlas = GlyphAtlas(device: device)

        let mtkView = MTKView(frame: frame, device: device)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = false
        mtkView.preferredFramesPerSecond = 60
        self.view = mtkView

        super.init()

        mtkView.delegate = self
        buildPipeline()
        allocateBuffers()
        updateClearColor()
    }

    // MARK: Pipeline Setup

    private func buildPipeline() {
        // Compile shaders from source at runtime.
        let shaderSource = Self.shaderSource
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunc = library.makeFunction(name: "glyphVertexShader")
            let fragmentFunc = library.makeFunction(name: "glyphFragmentShader")

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunc
            descriptor.fragmentFunction = fragmentFunc
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat

            // Premultiplied alpha blending for glyph compositing.
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("[MetalTextRenderer] Failed to build pipeline: \(error)")
        }
    }

    private func allocateBuffers() {
        let vertexSize = maxGlyphsPerFrame * 4 * MemoryLayout<GlyphVertex>.stride
        let indexSize = maxGlyphsPerFrame * 6 * MemoryLayout<UInt32>.stride
        vertexBuffer = device.makeBuffer(length: vertexSize, options: .storageModeShared)
        indexBuffer = device.makeBuffer(length: indexSize, options: .storageModeShared)
    }

    private func updateClearColor() {
        let c = backgroundColor.usingColorSpace(.sRGB) ?? backgroundColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        view.clearColor = MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: Double(a))
    }

    // MARK: Frame Rendering — MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Viewport changed; next draw will pick up the new size.
    }

    public func draw(in view: MTKView) {
        guard let pipelineState,
              let provider = viewportProvider,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        vertices.removeAll(keepingCapacity: true)
        indices.removeAll(keepingCapacity: true)

        let viewportWidth = Float(view.drawableSize.width)
        let viewportHeight = Float(view.drawableSize.height)

        // Build glyph quads for each visible line.
        let visibleRange = provider.visibleLineRange
        for lineNum in visibleRange {
            guard let line = provider.renderLine(at: lineNum) else { continue }
            appendGlyphs(for: line, lineIndex: lineNum - visibleRange.lowerBound,
                         viewportWidth: viewportWidth, viewportHeight: viewportHeight)
        }

        // Upload vertex/index data.
        guard !vertices.isEmpty,
              let vb = vertexBuffer, let ib = indexBuffer else { return }

        vertices.withUnsafeBufferPointer { src in
            memcpy(vb.contents(), src.baseAddress!, src.count * MemoryLayout<GlyphVertex>.stride)
        }
        indices.withUnsafeBufferPointer { src in
            memcpy(ib.contents(), src.baseAddress!, src.count * MemoryLayout<UInt32>.stride)
        }

        // Encode draw call.
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vb, offset: 0, index: 0)
        if let tex = glyphAtlas.texture {
            encoder.setFragmentTexture(tex, index: 0)
        }
        encoder.drawIndexedPrimitives(type: .triangle,
                                      indexCount: indices.count,
                                      indexType: .uint32,
                                      indexBuffer: ib,
                                      indexBufferOffset: 0)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: Glyph Quad Generation

    /// Decompose a `RenderLine` into glyph quads using CoreText for shaping.
    private func appendGlyphs(for renderLine: RenderLine,
                              lineIndex: Int,
                              viewportWidth: Float,
                              viewportHeight: Float) {
        let ctLine = CTLineCreateWithAttributedString(renderLine.attributedText)
        let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? []

        let baseY = Float(lineHeight) * Float(lineIndex)

        for run in runs {
            let glyphCount = CTRunGetGlyphCount(run)
            guard glyphCount > 0 else { continue }

            var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
            var positions = [CGPoint](repeating: .zero, count: glyphCount)
            CTRunGetGlyphs(run, CFRangeMake(0, glyphCount), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, glyphCount), &positions)

            // Extract font from the run attributes.
            let attrs = CTRunGetAttributes(run) as? [CFString: Any] ?? [:]
            let font = (attrs[kCTFontAttributeName] as! CTFont?)
                ?? CTFontCreateWithName("Menlo" as CFString, 13, nil)
            let fontSize = CTFontGetSize(font)

            // Determine color: use the first matching token color, or default.
            let stringRange = CTRunGetStringRange(run)
            let runColor = colorForRange(stringRange, tokens: renderLine.tokens)

            for i in 0..<glyphCount {
                guard vertices.count / 4 < maxGlyphsPerFrame else { return }

                guard let region = glyphAtlas.lookup(glyphID: glyphs[i], font: font,
                                                     size: fontSize, color: runColor) else {
                    continue
                }

                let px = Float(leftMargin) + Float(positions[i].x)
                let py = baseY + Float(positions[i].y)

                let (u0, v0, u1, v1) = region.texCoords(atlasWidth: glyphAtlas.atlasWidth,
                                                         atlasHeight: glyphAtlas.atlasHeight)

                let gw = Float(region.width)
                let gh = Float(region.height)

                // Convert pixel coords to normalized device coords (-1..1).
                let x0 = (px / viewportWidth) * 2.0 - 1.0
                let y0 = 1.0 - (py / viewportHeight) * 2.0
                let x1 = ((px + gw) / viewportWidth) * 2.0 - 1.0
                let y1 = 1.0 - ((py + gh) / viewportHeight) * 2.0

                let c = colorToSIMD(runColor)
                let baseIndex = UInt32(vertices.count)

                vertices.append(GlyphVertex(position: SIMD2(x0, y0), texCoord: SIMD2(u0, v0), color: c))
                vertices.append(GlyphVertex(position: SIMD2(x1, y0), texCoord: SIMD2(u1, v0), color: c))
                vertices.append(GlyphVertex(position: SIMD2(x1, y1), texCoord: SIMD2(u1, v1), color: c))
                vertices.append(GlyphVertex(position: SIMD2(x0, y1), texCoord: SIMD2(u0, v1), color: c))

                indices.append(contentsOf: [
                    baseIndex, baseIndex + 1, baseIndex + 2,
                    baseIndex, baseIndex + 2, baseIndex + 3
                ])
            }
        }
    }

    private func colorForRange(_ cfRange: CFRange, tokens: [(range: Range<Int>, color: NSColor)]) -> NSColor {
        let start = cfRange.location
        for token in tokens {
            if token.range.contains(start) {
                return token.color
            }
        }
        return .labelColor
    }

    private func colorToSIMD(_ color: NSColor) -> SIMD4<Float> {
        let c = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }

    // MARK: Shader Source

    /// Minimal Metal shading language source for textured glyph quads.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float2 position [[attribute(0)]];
        float2 texCoord [[attribute(1)]];
        float4 color    [[attribute(2)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
        float4 color;
    };

    struct GlyphVertex {
        packed_float2 position;
        packed_float2 texCoord;
        packed_float4 color;
    };

    vertex VertexOut glyphVertexShader(uint vid [[vertex_id]],
                                       const device GlyphVertex* vertices [[buffer(0)]]) {
        VertexOut out;
        out.position = float4(vertices[vid].position, 0.0, 1.0);
        out.texCoord = vertices[vid].texCoord;
        out.color = vertices[vid].color;
        return out;
    }

    fragment float4 glyphFragmentShader(VertexOut in [[stage_in]],
                                         texture2d<float> atlas [[texture(0)]]) {
        constexpr sampler s(mag_filter::linear, min_filter::linear);
        float4 texel = atlas.sample(s, in.texCoord);
        return float4(in.color.rgb, in.color.a * texel.a);
    }
    """
}
