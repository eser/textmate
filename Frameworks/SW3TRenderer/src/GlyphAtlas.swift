import Foundation
import Metal
import CoreGraphics
import CoreText
import AppKit

// MARK: - Glyph Cache Key

/// Uniquely identifies a rendered glyph variant in the atlas.
public struct GlyphCacheKey: Hashable, Sendable {
    public let glyphID: CGGlyph
    public let fontName: String
    public let fontSize: CGFloat
    public let colorHex: UInt32

    public init(glyphID: CGGlyph, font: CTFont, size: CGFloat, color: NSColor) {
        self.glyphID = glyphID
        self.fontName = CTFontCopyPostScriptName(font) as String
        self.fontSize = size
        self.colorHex = color.srgbHex
    }
}

// MARK: - Atlas Region

/// A rectangular region within the atlas texture.
public struct AtlasRegion: Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    /// Normalized texture coordinates for vertex shader sampling.
    public func texCoords(atlasWidth: Int, atlasHeight: Int) -> (u0: Float, v0: Float, u1: Float, v1: Float) {
        let aw = Float(atlasWidth)
        let ah = Float(atlasHeight)
        return (
            u0: Float(x) / aw,
            v0: Float(y) / ah,
            u1: Float(x + width) / aw,
            v1: Float(y + height) / ah
        )
    }
}

// MARK: - LRU Node

/// Doubly-linked list node for LRU eviction tracking.
final class LRUNode {
    let key: GlyphCacheKey
    let region: AtlasRegion
    var prev: LRUNode?
    var next: LRUNode?

    init(key: GlyphCacheKey, region: AtlasRegion) {
        self.key = key
        self.region = region
    }
}

// MARK: - Row Allocator

/// Row-based bin packing for the atlas texture.
/// Each row has a fixed height (tallest glyph placed so far) and glyphs
/// are packed left-to-right. When a row is full, a new row starts below.
struct RowAllocator {
    struct Row {
        var y: Int
        var height: Int
        var cursorX: Int
    }

    let atlasWidth: Int
    let atlasHeight: Int
    private(set) var rows: [Row] = []
    private var nextRowY: Int = 0

    init(width: Int, height: Int) {
        self.atlasWidth = width
        self.atlasHeight = height
    }

    /// Try to allocate a region of `width x height` pixels.
    /// Returns `nil` if the atlas is full.
    mutating func allocate(width w: Int, height h: Int) -> AtlasRegion? {
        guard w <= atlasWidth && h <= atlasHeight else { return nil }

        // Try to fit in an existing row that has enough remaining width and height.
        for i in rows.indices {
            if rows[i].cursorX + w <= atlasWidth && h <= rows[i].height {
                let region = AtlasRegion(x: rows[i].cursorX, y: rows[i].y, width: w, height: h)
                rows[i].cursorX += w
                return region
            }
        }

        // Start a new row.
        guard nextRowY + h <= atlasHeight else { return nil }
        let region = AtlasRegion(x: 0, y: nextRowY, width: w, height: h)
        rows.append(Row(y: nextRowY, height: h, cursorX: w))
        nextRowY += h
        return region
    }

    /// Reset the allocator, clearing all rows.
    mutating func reset() {
        rows.removeAll()
        nextRowY = 0
    }
}

// MARK: - Glyph Atlas

/// GPU texture atlas with LRU eviction for caching rasterized glyphs.
///
/// The atlas maintains a single `MTLTexture` of configurable size (default 2048x2048)
/// and packs glyphs into it using row-based allocation. When the atlas is full,
/// the least-recently-used glyphs are evicted and the atlas is rebuilt.
@MainActor
public final class GlyphAtlas {

    // MARK: Configuration

    public static let defaultAtlasSize = 2048

    // MARK: Properties

    public let device: MTLDevice
    public private(set) var texture: MTLTexture?
    public let atlasWidth: Int
    public let atlasHeight: Int

    private var cache: [GlyphCacheKey: LRUNode] = [:]
    private var lruHead: LRUNode?  // most recently used
    private var lruTail: LRUNode?  // least recently used
    private var allocator: RowAllocator
    private let maxEntries: Int

    /// Bitmap buffer reused across rasterization calls to avoid repeated allocation.
    private var rasterBuffer: [UInt8] = []

    // MARK: Init

    public init(device: MTLDevice,
                width: Int = GlyphAtlas.defaultAtlasSize,
                height: Int = GlyphAtlas.defaultAtlasSize,
                maxEntries: Int = 4096) {
        self.device = device
        self.atlasWidth = width
        self.atlasHeight = height
        self.maxEntries = maxEntries
        self.allocator = RowAllocator(width: width, height: height)
        self.texture = Self.makeTexture(device: device, width: width, height: height)
    }

    // MARK: Public API

    /// Look up or rasterize a glyph, returning its atlas region.
    /// The returned region's texture coordinates can be used directly for rendering.
    public func lookup(glyphID: CGGlyph, font: CTFont, size: CGFloat, color: NSColor) -> AtlasRegion? {
        let key = GlyphCacheKey(glyphID: glyphID, font: font, size: size, color: color)

        if let node = cache[key] {
            promoteToHead(node)
            return node.region
        }

        // Rasterize the glyph to a pixel buffer.
        guard let (pixels, w, h) = rasterize(glyphID: glyphID, font: font, color: color) else {
            return nil
        }

        // Attempt allocation, rebuilding if necessary.
        var region = allocator.allocate(width: w, height: h)
        if region == nil {
            rebuildAtlas()
            region = allocator.allocate(width: w, height: h)
        }
        guard let region else { return nil }

        // Upload pixels to the texture.
        uploadRegion(region, pixels: pixels, bytesPerRow: w * 4)

        // Insert into LRU cache.
        let node = LRUNode(key: key, region: region)
        cache[key] = node
        insertAtHead(node)

        // Evict if over capacity.
        while cache.count > maxEntries {
            evictLRU()
        }

        return region
    }

    /// Remove all cached glyphs and reset the atlas.
    public func clear() {
        cache.removeAll()
        lruHead = nil
        lruTail = nil
        allocator.reset()
        texture = Self.makeTexture(device: device, width: atlasWidth, height: atlasHeight)
    }

    /// Number of cached glyphs.
    public var count: Int { cache.count }

    // MARK: Rasterization

    /// Rasterize a single glyph into an RGBA pixel buffer using CoreGraphics.
    /// Returns `(pixels, width, height)` or `nil` on failure.
    public func rasterize(glyphID: CGGlyph, font: CTFont, color: NSColor) -> ([UInt8], Int, Int)? {
        var glyph = glyphID
        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, &boundingRect, 1)

        let padding: CGFloat = 2
        let w = Int(ceil(boundingRect.width + padding * 2))
        let h = Int(ceil(boundingRect.height + padding * 2))
        guard w > 0 && h > 0 else { return nil }

        let bytesPerRow = w * 4
        let totalBytes = bytesPerRow * h

        // Reuse buffer when possible.
        if rasterBuffer.count < totalBytes {
            rasterBuffer = [UInt8](repeating: 0, count: totalBytes)
        } else {
            rasterBuffer.withUnsafeMutableBufferPointer { ptr in
                ptr.baseAddress?.initialize(repeating: 0, count: totalBytes)
            }
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &rasterBuffer,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        // Resolve NSColor to CGColor for CoreGraphics.
        let resolved = color.usingColorSpace(.sRGB) ?? color
        let cgColor = resolved.cgColor
        context.setFillColor(cgColor)

        // Position the glyph so its bounding box sits within the bitmap.
        let originX = padding - boundingRect.origin.x
        let originY = padding - boundingRect.origin.y
        var position = CGPoint(x: originX, y: originY)

        CTFontDrawGlyphs(font, &glyph, &position, 1, context)

        let result = Array(rasterBuffer.prefix(totalBytes))
        return (result, w, h)
    }

    // MARK: Texture Management

    private static func makeTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        return device.makeTexture(descriptor: descriptor)
    }

    private func uploadRegion(_ region: AtlasRegion, pixels: [UInt8], bytesPerRow: Int) {
        guard let texture else { return }
        let mtlRegion = MTLRegion(
            origin: MTLOrigin(x: region.x, y: region.y, z: 0),
            size: MTLSize(width: region.width, height: region.height, depth: 1)
        )
        pixels.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            texture.replace(region: mtlRegion, mipmapLevel: 0,
                            withBytes: base, bytesPerRow: bytesPerRow)
        }
    }

    // MARK: LRU Linked List

    private func insertAtHead(_ node: LRUNode) {
        node.prev = nil
        node.next = lruHead
        lruHead?.prev = node
        lruHead = node
        if lruTail == nil { lruTail = node }
    }

    private func removeNode(_ node: LRUNode) {
        if node.prev != nil {
            node.prev?.next = node.next
        } else {
            lruHead = node.next
        }
        if node.next != nil {
            node.next?.prev = node.prev
        } else {
            lruTail = node.prev
        }
        node.prev = nil
        node.next = nil
    }

    private func promoteToHead(_ node: LRUNode) {
        guard node !== lruHead else { return }
        removeNode(node)
        insertAtHead(node)
    }

    private func evictLRU() {
        guard let tail = lruTail else { return }
        removeNode(tail)
        cache.removeValue(forKey: tail.key)
    }

    /// Rebuild the atlas by re-rasterizing and re-packing all cached glyphs
    /// in MRU order, dropping the least-recently-used half.
    private func rebuildAtlas() {
        // Collect entries in MRU order.
        var entries: [(key: GlyphCacheKey, node: LRUNode)] = []
        var cursor = lruHead
        while let node = cursor {
            entries.append((key: node.key, node: node))
            cursor = node.next
        }

        // Keep only the most-recently-used half.
        let keepCount = max(entries.count / 2, 1)
        let kept = entries.prefix(keepCount)

        // Reset everything.
        cache.removeAll()
        lruHead = nil
        lruTail = nil
        allocator.reset()
        texture = Self.makeTexture(device: device, width: atlasWidth, height: atlasHeight)

        // Re-insert kept entries by re-rasterizing.
        for entry in kept.reversed() {
            let key = entry.key
            // We need to reconstruct the font from the key.
            guard let font = CTFontCreateWithName(key.fontName as CFString, key.fontSize, nil) as CTFont? else {
                continue
            }
            let color = NSColor.fromSrgbHex(key.colorHex)
            _ = lookup(glyphID: key.glyphID, font: font, size: key.fontSize, color: color)
        }
    }
}

// MARK: - NSColor Hex Helpers

extension NSColor {
    /// Convert to a 32-bit sRGB hex value for use as a hash key.
    var srgbHex: UInt32 {
        let resolved = usingColorSpace(.sRGB) ?? self
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = UInt32(r * 255) & 0xFF
        let gi = UInt32(g * 255) & 0xFF
        let bi = UInt32(b * 255) & 0xFF
        let ai = UInt32(a * 255) & 0xFF
        return (ri << 24) | (gi << 16) | (bi << 8) | ai
    }

    /// Reconstruct an NSColor from a 32-bit sRGB hex value.
    static func fromSrgbHex(_ hex: UInt32) -> NSColor {
        let r = CGFloat((hex >> 24) & 0xFF) / 255.0
        let g = CGFloat((hex >> 16) & 0xFF) / 255.0
        let b = CGFloat((hex >> 8) & 0xFF) / 255.0
        let a = CGFloat(hex & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
