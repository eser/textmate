// SW³ TextFellow — Metal Shaders
// SPDX-License-Identifier: GPL-3.0-or-later

#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────
// MARK: - Glyph Rendering (textured quads)
// ─────────────────────────────────────────────

/// Per-vertex data for glyph rendering.
/// Each glyph is a textured quad (2 triangles, 6 vertices via index buffer).
struct GlyphVertex {
    float2 position   [[attribute(0)]]; // Screen position
    float2 texCoord   [[attribute(1)]]; // UV in glyph atlas
    float4 color      [[attribute(2)]]; // Syntax highlight color (per-vertex)
};

struct GlyphFragmentData {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

/// Viewport uniforms — projection matrix for screen coordinates.
struct Uniforms {
    float4x4 projectionMatrix;
};

vertex GlyphFragmentData glyph_vertex(
    const device GlyphVertex* vertices [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    GlyphFragmentData out;
    out.position = uniforms.projectionMatrix * float4(vertices[vid].position, 0.0, 1.0);
    out.texCoord = vertices[vid].texCoord;
    out.color = vertices[vid].color;
    return out;
}

fragment float4 glyph_fragment(
    GlyphFragmentData in [[stage_in]],
    texture2d<float> atlas [[texture(0)]],
    sampler atlasSampler [[sampler(0)]]
) {
    float4 texColor = atlas.sample(atlasSampler, in.texCoord);
    // Use atlas alpha for glyph shape, vertex color for tint
    return float4(in.color.rgb, in.color.a * texColor.a);
}

// ─────────────────────────────────────────────
// MARK: - Rect Rendering (selections, caret, backgrounds)
// ─────────────────────────────────────────────

/// Per-vertex data for filled rectangles.
struct RectVertex {
    float2 position   [[attribute(0)]]; // Screen position
    float4 color      [[attribute(1)]]; // Fill color
};

struct RectFragmentData {
    float4 position [[position]];
    float4 color;
};

vertex RectFragmentData rect_vertex(
    const device RectVertex* vertices [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]],
    uint vid [[vertex_id]]
) {
    RectFragmentData out;
    out.position = uniforms.projectionMatrix * float4(vertices[vid].position, 0.0, 1.0);
    out.color = vertices[vid].color;
    return out;
}

fragment float4 rect_fragment(
    RectFragmentData in [[stage_in]]
) {
    return in.color;
}

// ─────────────────────────────────────────────
// MARK: - Cursor Rendering (animated caret)
// ─────────────────────────────────────────────

/// Cursor uses the rect pipeline with animated alpha.
/// The animation is computed on the CPU side (position lerp + easing)
/// and passed as the alpha component of the color.
