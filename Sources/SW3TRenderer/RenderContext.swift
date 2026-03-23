// SW³ TextFellow — Metal Render Context
// SPDX-License-Identifier: GPL-3.0-or-later

import Metal
import MetalKit

/// Central Metal state shared across all renderers.
///
/// ```
///  RenderContext
///  ├── MTLDevice            — GPU handle
///  ├── MTLCommandQueue      — frame submission
///  ├── MTLLibrary           — compiled shaders
///  ├── GlyphAtlas           — shared glyph texture cache
///  └── frame timing         — ProMotion 120fps target
/// ```
public final class RenderContext: Sendable {
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let library: MTLLibrary

    /// Initialize with the default system GPU.
    /// Returns nil if Metal is unavailable (CI, headless environments).
    public init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }

        // Load pre-compiled shader library from the module bundle.
        // Falls back to default library if bundle shaders aren't found.
        let library: MTLLibrary
        if let bundleLib = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            library = bundleLib
        } else if let defaultLib = device.makeDefaultLibrary() {
            library = defaultLib
        } else {
            return nil
        }

        self.device = device
        self.commandQueue = commandQueue
        self.library = library
    }

    /// The maximum GPU family supported — determines available features.
    public var gpuFamily: String {
        if device.supportsFamily(.apple9) { return "apple9 (M3/M4)" }
        if device.supportsFamily(.apple8) { return "apple8 (M2)" }
        if device.supportsFamily(.apple7) { return "apple7 (M1)" }
        if device.supportsFamily(.common3) { return "common3 (Intel AMD)" }
        return "unknown"
    }
}

/// A no-op render context for CI and headless environments.
/// The failure posture for MTLDevice unavailability is "degrade" —
/// tests run without GPU, the renderer produces no output.
public final class NoOpRenderContext: Sendable {
    public static let shared = NoOpRenderContext()
    public init() {}
}
