// SW³ TextFellow — Metal Text Layer
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Phase 1 of Metal rendering: CoreText renders into a CGContext backed by
// a Metal texture. Same visual quality as the current renderer, but the
// compositing moves to GPU. Phase 2 (glyph atlas) replaces the CGContext
// rasterization with direct GPU glyph drawing.
//
// This layer can be placed OVER the existing OakTextView to visually
// replace its rendering while keeping the interaction model intact.

import AppKit
import MetalKit
import CoreText

/// Renders text lines into a Metal texture using CoreText for layout.
///
/// ```
///  Document text ──► CoreText layout (CTLine/CTRun)
///       │
///       ▼
///  CGContext (backed by MTLTexture via CGBitmapContext)
///       │
///       ▼
///  MTKView draws the texture as a fullscreen quad
/// ```
@objc(SW3TMetalTextLayer)
class MetalTextLayer: NSObject {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var texture: MTLTexture?
    private var textureWidth: Int = 0
    private var textureHeight: Int = 0

    @objc init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        super.init()
    }

    /// Render attributed text lines into a Metal texture.
    /// Returns the texture ready for display in an MTKView.
    func render(
        lines: [(text: NSAttributedString, origin: CGPoint)],
        viewportSize: CGSize,
        backgroundColor: NSColor,
        scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
    ) -> MTLTexture? {
        let width = Int(viewportSize.width * scale)
        let height = Int(viewportSize.height * scale)

        // Recreate texture if size changed
        if width != textureWidth || height != textureHeight {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width, height: height,
                mipmapped: false
            )
            desc.usage = [.shaderRead, .renderTarget]
            texture = device.makeTexture(descriptor: desc)
            textureWidth = width
            textureHeight = height
        }

        guard let texture else { return nil }

        // Create a CGContext backed by a buffer we'll copy to the Metal texture
        let bytesPerRow = width * 4
        let bufferSize = bytesPerRow * height
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        guard let cgContext = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Scale for Retina
        cgContext.scaleBy(x: scale, y: scale)

        // Flip coordinate system (CoreText uses bottom-up)
        cgContext.translateBy(x: 0, y: viewportSize.height)
        cgContext.scaleBy(x: 1, y: -1)

        // Fill background
        let bg = backgroundColor.usingColorSpace(.sRGB) ?? backgroundColor
        cgContext.setFillColor(CGColor(
            srgbRed: bg.redComponent, green: bg.greenComponent,
            blue: bg.blueComponent, alpha: bg.alphaComponent
        ))
        cgContext.fill(CGRect(origin: .zero, size: viewportSize))

        // Draw each line using CoreText
        for (attrText, origin) in lines {
            let line = CTLineCreateWithAttributedString(attrText)
            cgContext.textPosition = CGPoint(x: origin.x, y: origin.y)
            CTLineDraw(line, cgContext)
        }

        // Copy bitmap to Metal texture
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                               size: MTLSize(width: width, height: height, depth: 1))
        buffer.withUnsafeBufferPointer { ptr in
            texture.replace(region: region, mipmapLevel: 0,
                           withBytes: ptr.baseAddress!, bytesPerRow: bytesPerRow)
        }

        return texture
    }
}
