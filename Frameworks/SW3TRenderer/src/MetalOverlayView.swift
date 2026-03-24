// SW³ TextFellow — Metal Rendering Overlay
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Full-opacity MTKView overlay on OakTextView that renders text via
// MetalFullRenderer (GPU glyph atlas pipeline). CoreText still runs
// underneath for hit-testing, IME, and accessibility.
//
// Toggle: defaults write org.sw3t.TextFellow metalRenderer -bool YES/NO

import AppKit
import MetalKit
import os.log

@objc(SW3TMetalOverlayView)
class MetalOverlayView: MTKView, @preconcurrency MTKViewDelegate {
    private let renderer: MetalFullRenderer?
    private var pendingLines: [(text: NSAttributedString, origin: CGPoint, syntaxColor: NSColor?)] = []
    private var pendingSelections: [MetalSelectionRect] = []
    private var pendingCursor: MetalCursorInfo?
    private var hasRenderedOnce = false
    private var pendingBackgroundColor: NSColor = .textBackgroundColor
    private var pendingScrollY: CGFloat = 0

    @objc init?(parentView: NSView) {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        let renderer = MetalFullRenderer(device: device)
        self.renderer = renderer

        super.init(frame: parentView.bounds, device: device)
        self.delegate = self
        self.isPaused = true
        self.enableSetNeedsDisplay = true

        // Retina: match parent's backing scale factor
        let scale = parentView.window?.backingScaleFactor ?? 2.0
        self.layer?.contentsScale = scale
        self.colorPixelFormat = .bgra8Unorm

        // Start transparent — switch to opaque after first successful render
        self.layer?.isOpaque = false
        self.alphaValue = 0.0

        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        // Track parent view size
        self.autoresizingMask = [.width, .height]
        self.frame = parentView.bounds
        parentView.addSubview(self, positioned: .above, relativeTo: nil)

        // Observe frame changes to keep in sync
        self.postsFrameChangedNotifications = true

        let dbg = DebugLogger.shared
        if renderer != nil {
            dbg.log("METAL", "MetalOverlayView created — renderer OK, alpha=\(self.alphaValue), opaque=\(self.layer?.isOpaque ?? false)")
            dbg.log("METAL", "device=\(device.name)")
        } else {
            dbg.log("METAL", "ERROR: MetalFullRenderer init FAILED — CoreText fallback")
        }
    }

    required init(coder: NSCoder) { fatalError() }

    // Match OakTextView's flipped coordinate system (y=0 at top)
    override var isFlipped: Bool { true }

    // MARK: - Public Bridge (called from OakTextView)

    /// Render document content via Metal GPU pipeline.
    /// Call from OakTextView via performSelector:withObject: passing NSDictionary.
    /// Keys: "lines" ([NSAttributedString]), "origins" ([NSValue]),
    ///        "selections" ([[String:Any]]), "cursor" ([String:Any]?), "bg" (NSColor)
    @objc func renderDocumentData(_ data: NSDictionary) {
        guard let lines = data["lines"] as? [NSAttributedString],
              let origins = data["origins"] as? [NSValue] else {
            DebugLogger.shared.log("METAL", "renderDocumentData: MISSING lines or origins in data keys=\(data.allKeys)")
            return
        }
        DebugLogger.shared.log("METAL", "renderDocumentData: \(lines.count) lines, \(origins.count) origins")

        // Convert line data
        pendingLines = zip(lines, origins).map { (text, originVal) in
            (text: text, origin: originVal.pointValue, syntaxColor: nil as NSColor?)
        }

        // Convert selection rects
        if let selections = data["selections"] as? [[String: Any]] {
            pendingSelections = selections.compactMap { dict in
                guard let x = dict["x"] as? CGFloat,
                      let y = dict["y"] as? CGFloat,
                      let w = dict["width"] as? CGFloat,
                      let h = dict["height"] as? CGFloat else { return nil }
                let color = (dict["color"] as? NSColor) ?? NSColor.selectedTextBackgroundColor
                return MetalSelectionRect(rect: CGRect(x: x, y: y, width: w, height: h), color: color)
            }
        }

        // Convert cursor
        if let cursor = data["cursor"] as? [String: Any],
           let cx = cursor["x"] as? CGFloat,
           let cy = cursor["y"] as? CGFloat,
           let ch = cursor["h"] as? CGFloat {
            pendingCursor = MetalCursorInfo(
                position: CGPoint(x: cx, y: cy),
                height: ch,
                color: .textColor,
                blinkPhase: 1.0
            )
        } else {
            pendingCursor = nil
        }

        pendingBackgroundColor = (data["bg"] as? NSColor) ?? .textBackgroundColor
        pendingScrollY = (data["scrollY"] as? CGFloat) ?? 0
        needsDisplay = true
    }

    /// Legacy method — render text from attributed strings (Phase 1 compatibility).
    @objc func renderText(lines: [NSAttributedString], origins: [NSValue], backgroundColor: NSColor) {
        renderDocumentData([
            "lines": lines,
            "origins": origins,
            "bg": backgroundColor,
        ] as NSDictionary)
    }

    /// Legacy method — update colored bars (demo overlay).
    @objc func updateBars(_ newBars: [[String: Any]]) {
        // Deprecated — MetalFullRenderer handles all rendering now
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let renderer,
              !pendingLines.isEmpty,
              let drawable = currentDrawable,
              let renderPass = currentRenderPassDescriptor else { return }

        // Set background clear color
        let bg = pendingBackgroundColor.usingColorSpace(.sRGB) ?? pendingBackgroundColor
        renderPass.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(bg.redComponent),
            green: Double(bg.greenComponent),
            blue: Double(bg.blueComponent),
            alpha: 1.0
        )
        renderPass.colorAttachments[0].loadAction = .clear

        // Scale factor: drawableSize is in pixels, positions are in points
        let scale = view.drawableSize.width / max(view.bounds.width, 1)

        // Scale from points to pixels (positions already relative to visible rect)
        let scaledLines = pendingLines.map { line -> (text: NSAttributedString, origin: CGPoint, syntaxColor: NSColor?) in
            (text: line.text,
             origin: CGPoint(x: line.origin.x * scale, y: line.origin.y * scale),
             syntaxColor: line.syntaxColor)
        }

        let scaledSelections = pendingSelections.map { sel -> MetalSelectionRect in
            MetalSelectionRect(
                rect: CGRect(x: sel.rect.origin.x * scale, y: sel.rect.origin.y * scale,
                             width: sel.rect.width * scale, height: sel.rect.height * scale),
                color: sel.color)
        }

        var scaledCursor = pendingCursor
        if var c = scaledCursor {
            c.position = CGPoint(x: c.position.x * scale, y: c.position.y * scale)
            c.height *= scale
            scaledCursor = c
        }

        renderer.renderFrame(
            to: drawable,
            renderPass: renderPass,
            viewport: view.drawableSize,
            lines: scaledLines,
            selections: scaledSelections,
            cursor: scaledCursor,
            backgroundColor: pendingBackgroundColor,
            backingScale: scale
        )

        // First successful render — go opaque to replace CoreText
        if !hasRenderedOnce {
            hasRenderedOnce = true
            self.layer?.isOpaque = true
            self.alphaValue = 1.0
            DebugLogger.shared.log("METAL", "FIRST RENDER — going opaque, \(pendingLines.count) lines rendered")
        }
    }
}
