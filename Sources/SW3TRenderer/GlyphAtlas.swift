// SW³ TextFellow — Glyph Atlas
// SPDX-License-Identifier: GPL-3.0-or-later

import Metal
import CoreGraphics
import CoreText

/// GPU texture atlas for cached glyph bitmaps.
///
/// ```
///  Glyph Atlas Architecture:
///
///  ┌──────────────────────────────────────┐
///  │         MTLTexture (2048²)           │  ← Tier 1: Latin/common
///  │  ┌──┐┌──┐┌──┐┌──┐┌──┐             │
///  │  │ A││ B││ C││ a││ b│  ...         │
///  │  └──┘└──┘└──┘└──┘└──┘             │
///  │  ┌───┐┌────┐┌──┐                    │
///  │  │ ( ││ // ││ { │  ...             │
///  │  └───┘└────┘└──┘                    │
///  └──────────────────────────────────────┘
///
///  ┌──────────────────────────────────────┐
///  │         MTLTexture (4096²)           │  ← Tier 2: CJK (on-demand)
///  │  ┌────┐┌────┐┌────┐┌────┐          │
///  │  │ 你 ││ 好 ││ 世 ││ 界 │  ...    │
///  │  └────┘└────┘└────┘└────┘          │
///  └──────────────────────────────────────┘
///
///  Lookup: (glyphID, font, size) → AtlasRegion { page, uv_rect }
///  Eviction: LRU per-page when atlas is full
/// ```
public final class GlyphAtlas {
    /// A region within the atlas texture.
    public struct Region: Sendable {
        /// Which texture page this glyph lives on.
        public let page: Int
        /// UV coordinates within the texture (0..1).
        public let uvRect: CGRect
        /// Size in pixels of the rasterized glyph.
        public let pixelSize: CGSize
        /// Bearing offset for correct positioning.
        public let bearing: CGPoint
    }

    /// Key for atlas lookup — uniquely identifies a rasterized glyph.
    public struct GlyphKey: Hashable, Sendable {
        public let glyphID: CGGlyph
        public let fontName: String
        public let fontSize: CGFloat
        public let scale: CGFloat  // Retina factor

        public init(glyphID: CGGlyph, fontName: String, fontSize: CGFloat, scale: CGFloat) {
            self.glyphID = glyphID
            self.fontName = fontName
            self.fontSize = fontSize
            self.scale = scale
        }
    }

    private let device: MTLDevice
    private var pages: [AtlasPage]
    private var cache: [GlyphKey: Region] = [:]
    private var lruOrder: [GlyphKey] = []
    private let tier1Size: Int = 2048
    private let tier2Size: Int = 4096
    private var cjkDetected: Bool = false

    public init(device: MTLDevice) {
        self.device = device
        self.pages = []
        // Create tier 1 page immediately
        if let page = AtlasPage(device: device, size: tier1Size) {
            pages.append(page)
        }
    }

    /// Look up or rasterize a glyph, returning its atlas region.
    public func region(for key: GlyphKey) -> Region? {
        // Cache hit — move to front of LRU
        if let cached = cache[key] {
            touchLRU(key)
            return cached
        }

        // Cache miss — rasterize and upload
        return rasterizeAndCache(key)
    }

    /// Check if CJK tier-2 page has been allocated.
    public var hasCJKPage: Bool { cjkDetected }

    /// Number of cached glyphs.
    public var cachedGlyphCount: Int { cache.count }

    /// Number of texture pages.
    public var pageCount: Int { pages.count }

    // MARK: - Private

    private func rasterizeAndCache(_ key: GlyphKey) -> Region? {
        // Detect CJK and allocate tier 2 if needed
        if isCJKGlyph(key.glyphID) && !cjkDetected {
            cjkDetected = true
            if let page = AtlasPage(device: device, size: tier2Size) {
                pages.append(page)
            }
        }

        // Find a page with space
        let targetPage = cjkDetected && isCJKGlyph(key.glyphID) ? pages.count - 1 : 0
        guard targetPage < pages.count else { return nil }

        let page = pages[targetPage]

        // Rasterize glyph to bitmap
        guard let bitmap = rasterizeGlyph(key) else { return nil }

        // Try to allocate space in the page
        guard let allocation = page.allocate(
            width: bitmap.width,
            height: bitmap.height
        ) else {
            // Page full — evict LRU glyphs from this page
            evictLRU(page: targetPage, needed: bitmap.width * bitmap.height)
            guard let retryAllocation = page.allocate(
                width: bitmap.width,
                height: bitmap.height
            ) else { return nil }
            return uploadAndCache(key, bitmap: bitmap, allocation: retryAllocation, page: targetPage)
        }

        return uploadAndCache(key, bitmap: bitmap, allocation: allocation, page: targetPage)
    }

    private func uploadAndCache(
        _ key: GlyphKey,
        bitmap: GlyphBitmap,
        allocation: AtlasAllocation,
        page: Int
    ) -> Region {
        let pageObj = pages[page]

        // Upload bitmap to texture
        let bytesPerRow = bitmap.width * 4
        pageObj.texture.replace(
            region: MTLRegionMake2D(allocation.x, allocation.y, bitmap.width, bitmap.height),
            mipmapLevel: 0,
            withBytes: bitmap.data,
            bytesPerRow: bytesPerRow
        )

        let texSize = CGFloat(pageObj.size)
        let region = Region(
            page: page,
            uvRect: CGRect(
                x: CGFloat(allocation.x) / texSize,
                y: CGFloat(allocation.y) / texSize,
                width: CGFloat(bitmap.width) / texSize,
                height: CGFloat(bitmap.height) / texSize
            ),
            pixelSize: CGSize(width: bitmap.width, height: bitmap.height),
            bearing: bitmap.bearing
        )

        cache[key] = region
        lruOrder.append(key)
        return region
    }

    private func rasterizeGlyph(_ key: GlyphKey) -> GlyphBitmap? {
        guard let font = CTFontCreateWithName(key.fontName as CFString, key.fontSize * key.scale, nil) as CTFont? else {
            return nil
        }

        var glyph = key.glyphID
        var boundingRect = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, &boundingRect, 1)

        let width = Int(ceil(boundingRect.width)) + 2
        let height = Int(ceil(boundingRect.height)) + 2
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)

        // Draw glyph
        let origin = CGPoint(
            x: -boundingRect.origin.x + 1,
            y: -boundingRect.origin.y + 1
        )
        var position = origin
        CTFontDrawGlyphs(font, &glyph, &position, 1, context)

        return GlyphBitmap(
            data: pixelData,
            width: width,
            height: height,
            bearing: CGPoint(x: boundingRect.origin.x - 1, y: boundingRect.origin.y - 1)
        )
    }

    private func touchLRU(_ key: GlyphKey) {
        if let idx = lruOrder.firstIndex(of: key) {
            lruOrder.remove(at: idx)
            lruOrder.append(key)
        }
    }

    private func evictLRU(page: Int, needed: Int) {
        var freed = 0
        while freed < needed, !lruOrder.isEmpty {
            let evictKey = lruOrder.removeFirst()
            if let region = cache[evictKey], region.page == page {
                cache.removeValue(forKey: evictKey)
                freed += Int(region.pixelSize.width * region.pixelSize.height)
            }
        }
    }

    /// Heuristic: CJK unified ideographs range.
    private func isCJKGlyph(_ glyphID: CGGlyph) -> Bool {
        // This is a rough heuristic — in practice we'd check the
        // Unicode codepoint, not the glyph ID. For now, we detect
        // CJK by checking if the glyph atlas is being pressured
        // (>500 unique glyphs suggests CJK content).
        cachedGlyphCount > 500
    }
}

// MARK: - Supporting types

struct GlyphBitmap {
    let data: [UInt8]
    let width: Int
    let height: Int
    let bearing: CGPoint
}

struct AtlasAllocation {
    let x: Int
    let y: Int
}

/// A single texture page in the atlas.
class AtlasPage {
    let texture: MTLTexture
    let size: Int
    private var nextX: Int = 0
    private var nextY: Int = 0
    private var rowHeight: Int = 0

    init?(device: MTLDevice, size: Int) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared // Unified memory on Apple Silicon

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        self.texture = texture
        self.size = size
    }

    /// Simple row-based allocator. Packs glyphs left-to-right,
    /// top-to-bottom. Not space-optimal but fast.
    func allocate(width: Int, height: Int) -> AtlasAllocation? {
        guard width > 0, height > 0 else { return nil }

        // Check if glyph fits in current row
        if nextX + width > size {
            // Move to next row
            nextX = 0
            nextY += rowHeight + 1
            rowHeight = 0
        }

        // Check if we've exceeded the texture
        if nextY + height > size {
            return nil // Page full
        }

        let allocation = AtlasAllocation(x: nextX, y: nextY)
        nextX += width + 1 // 1px padding between glyphs
        rowHeight = max(rowHeight, height)
        return allocation
    }
}
