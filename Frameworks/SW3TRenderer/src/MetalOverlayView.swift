// SW³ TextFellow — Metal Syntax Overlay (Debug/Preview)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Opt-in Metal overlay that renders tree-sitter syntax colors as
// semi-transparent bars over the existing CoreText rendering.
// Proves the Metal pipeline works without replacing the editor.
//
// Enable: defaults write org.sw3t.TextFellow metalOverlay -bool YES

import AppKit
import MetalKit

/// A transparent MTKView overlay that visualizes tree-sitter parse results
/// on top of the existing OakTextView rendering.
@objc(SW3TMetalOverlayView)
class MetalOverlayView: MTKView, @preconcurrency MTKViewDelegate {
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?

    struct ColorBar {
        var x: Float, y: Float, width: Float, height: Float
        var r: Float, g: Float, b: Float, a: Float
    }

    private var bars: [ColorBar] = []

    @objc init?(parentView: NSView) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        super.init(frame: parentView.bounds, device: device)
        self.commandQueue = device.makeCommandQueue()
        self.delegate = self
        self.isPaused = true
        self.enableSetNeedsDisplay = true
        self.layer?.isOpaque = false
        self.alphaValue = 0.15 // subtle overlay

        self.autoresizingMask = [.width, .height]
        parentView.addSubview(self, positioned: .above, relativeTo: nil)

        setupPipeline()
    }

    required init(coder: NSCoder) { fatalError() }

    // MARK: - Public

    @objc func updateBars(_ newBars: [[String: Any]]) {
        bars = newBars.compactMap { dict in
            guard let x = dict["x"] as? CGFloat,
                  let y = dict["y"] as? CGFloat,
                  let w = dict["width"] as? CGFloat,
                  let h = dict["height"] as? CGFloat,
                  let color = dict["color"] as? NSColor else { return nil }
            let rgb = color.usingColorSpace(.sRGB) ?? color
            return ColorBar(
                x: Float(x), y: Float(y), width: Float(w), height: Float(h),
                r: Float(rgb.redComponent), g: Float(rgb.greenComponent),
                b: Float(rgb.blueComponent), a: Float(rgb.alphaComponent)
            )
        }
        needsDisplay = true
    }

    // MARK: - Pipeline

    private func setupPipeline() {
        guard let device else { return }

        let shaderSrc = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float4 color;
        };

        vertex VertexOut vertex_main(
            uint vid [[vertex_id]],
            constant float4* rects [[buffer(0)]],
            constant float4* colors [[buffer(1)]],
            constant float2& viewport [[buffer(2)]]
        ) {
            uint rectIdx = vid / 6;
            uint corner = vid % 6;

            float4 rect = rects[rectIdx];
            float x = rect.x, y = rect.y, w = rect.z, h = rect.w;

            float2 pos;
            switch(corner) {
                case 0: pos = float2(x, y); break;
                case 1: pos = float2(x+w, y); break;
                case 2: pos = float2(x, y+h); break;
                case 3: pos = float2(x+w, y); break;
                case 4: pos = float2(x+w, y+h); break;
                case 5: pos = float2(x, y+h); break;
            }

            VertexOut out;
            out.position = float4(pos.x / viewport.x * 2.0 - 1.0,
                                  1.0 - pos.y / viewport.y * 2.0, 0, 1);
            out.color = colors[rectIdx];
            return out;
        }

        fragment float4 fragment_main(VertexOut in [[stage_in]]) {
            return in.color;
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSrc, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "vertex_main")
            desc.fragmentFunction = library.makeFunction(name: "fragment_main")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            os_log(.error, "MetalOverlay: pipeline setup failed: %{public}@", error.localizedDescription)
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard !bars.isEmpty,
              let pipeline = pipelineState,
              let drawable = currentDrawable,
              let desc = currentRenderPassDescriptor,
              let cmdBuf = commandQueue?.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: desc) else { return }

        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        let rects = bars.map { SIMD4<Float>($0.x, $0.y, $0.width, $0.height) }
        let colors = bars.map { SIMD4<Float>($0.r, $0.g, $0.b, $0.a) }
        var viewport = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(rects, length: rects.count * MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.setVertexBytes(colors, length: colors.count * MemoryLayout<SIMD4<Float>>.size, index: 1)
        encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: bars.count * 6)
        encoder.endEncoding()

        cmdBuf.present(drawable)
        cmdBuf.commit()
    }
}
