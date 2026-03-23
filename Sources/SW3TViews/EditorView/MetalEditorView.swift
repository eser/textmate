// SW³ TextFellow — Metal Editor View (NSViewRepresentable)
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Wraps MTKView in SwiftUI. This is the ONLY place NSViewRepresentable
// is used for the editor rendering surface. Everything else is SwiftUI.
//
//  ┌──────────────────────────────────────────────┐
//  │  SwiftUI                                     │
//  │  ┌────────────────────────────────────────┐  │
//  │  │  MetalEditorView (NSViewRepresentable) │  │
//  │  │  ┌──────────────────────────────────┐  │  │
//  │  │  │  MTKView                         │  │  │
//  │  │  │  (GPU-rendered text, glyph atlas) │  │  │
//  │  │  └──────────────────────────────────┘  │  │
//  │  └────────────────────────────────────────┘  │
//  └──────────────────────────────────────────────┘

#if canImport(AppKit)
import SwiftUI
import MetalKit
import SW3TRenderer
import SW3TViewport

/// SwiftUI wrapper around the Metal text rendering surface.
public struct MetalEditorView: NSViewRepresentable {
    let renderer: TextEditorRenderer
    let viewportProvider: any ViewportProvider

    public init(renderer: TextEditorRenderer, viewportProvider: any ViewportProvider) {
        self.renderer = renderer
        self.viewportProvider = viewportProvider
    }

    public func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = renderer.context.device
        mtkView.delegate = renderer
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        mtkView.preferredFramesPerSecond = 120 // ProMotion target
        mtkView.enableSetNeedsDisplay = false  // Continuous rendering for animations
        mtkView.isPaused = false

        renderer.viewportProvider = viewportProvider

        return mtkView
    }

    public func updateNSView(_ mtkView: MTKView, context: Context) {
        renderer.viewportProvider = viewportProvider
    }
}
#endif

#if canImport(UIKit) && !os(macOS)
import SwiftUI
import MetalKit
import SW3TRenderer
import SW3TViewport

/// SwiftUI wrapper for iOS/iPadOS.
public struct MetalEditorView: UIViewRepresentable {
    let renderer: TextEditorRenderer
    let viewportProvider: any ViewportProvider

    public init(renderer: TextEditorRenderer, viewportProvider: any ViewportProvider) {
        self.renderer = renderer
        self.viewportProvider = viewportProvider
    }

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = renderer.context.device
        mtkView.delegate = renderer
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 120
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        renderer.viewportProvider = viewportProvider

        return mtkView
    }

    public func updateUIView(_ mtkView: MTKView, context: Context) {
        renderer.viewportProvider = viewportProvider
    }
}
#endif
