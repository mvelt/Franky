#include <metal_stdlib>
#include "ShaderTypes.h"

using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Colour palettes
// ─────────────────────────────────────────────────────────────────────────────

static float3 cosineGradient(float t, float3 a, float3 b, float3 c, float3 d) {
    return clamp(a + b * cos(6.28318530718f * (c * t + d)), 0.0f, 1.0f);
}

static float3 paletteColor(float t, int palette) {
    // t is already wrapped to [0, 1) by the caller
    switch (palette) {
        case 0: // Classic — cool blue → warm orange
            return cosineGradient(t,
                float3(0.5f, 0.5f, 0.5f), float3(0.5f, 0.5f, 0.5f),
                float3(1.0f, 1.0f, 1.0f), float3(0.00f, 0.10f, 0.20f));

        case 1: // Fire — black → red → orange → yellow
            return cosineGradient(t,
                float3(0.5f, 0.0f, 0.0f), float3(0.5f, 0.35f, 0.05f),
                float3(1.0f, 0.70f, 0.40f), float3(0.00f, 0.10f, 0.15f));

        case 2: // Ocean — deep blue → teal → cyan → white
            return cosineGradient(t,
                float3(0.2f, 0.5f, 0.7f), float3(0.2f, 0.4f, 0.3f),
                float3(0.5f, 0.8f, 1.0f), float3(0.50f, 0.25f, 0.00f));

        case 3: // Neon — vivid rainbow cycling rapidly
            return cosineGradient(t,
                float3(0.5f, 0.5f, 0.5f), float3(0.5f, 0.5f, 0.5f),
                float3(2.0f, 1.0f, 0.5f), float3(0.50f, 0.20f, 0.25f));

        case 4: // Purple Haze — dark purple → violet → lavender
            return cosineGradient(t,
                float3(0.4f, 0.2f, 0.5f), float3(0.4f, 0.2f, 0.4f),
                float3(0.8f, 0.5f, 1.0f), float3(0.00f, 0.20f, 0.40f));

        case 5: // Sunset — deep red → orange → gold → pink
            return cosineGradient(t,
                float3(0.5f, 0.3f, 0.3f), float3(0.5f, 0.3f, 0.2f),
                float3(0.8f, 0.6f, 0.3f), float3(0.00f, 0.10f, 0.50f));

        case 6: // Ice — pale blue → white → pale cyan
            return cosineGradient(t,
                float3(0.7f, 0.9f, 1.0f), float3(0.3f, 0.1f, 0.0f),
                float3(0.5f, 0.5f, 1.0f), float3(0.00f, 0.10f, 0.20f));

        case 7: // Forest — dark green → lime → amber
            return cosineGradient(t,
                float3(0.2f, 0.4f, 0.1f), float3(0.2f, 0.3f, 0.2f),
                float3(1.0f, 0.7f, 0.5f), float3(0.20f, 0.40f, 0.60f));

        default:
            return float3(t, t, t); // Greyscale fallback
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Fractal compute kernel
// ─────────────────────────────────────────────────────────────────────────────

kernel void fractalKernel(
    texture2d<float, access::write> output  [[texture(0)]],
    constant FractalParams&         p       [[buffer(0)]],
    uint2                           gid     [[thread_position_in_grid]]
) {
    const uint W = uint(p.viewWidth);
    const uint H = uint(p.viewHeight);
    if (gid.x >= W || gid.y >= H) return;

    // Map pixel → fractal coordinate
    const float scale = 1.0f / (p.zoom * min(p.viewWidth, p.viewHeight));
    float cx = p.centerX + (float(gid.x) - p.viewWidth  * 0.5f) * scale;
    float cy = p.centerY + (float(gid.y) - p.viewHeight * 0.5f) * scale;

    float zx, zy, jx, jy;

    if (p.fractalType == 0) {
        // Mandelbrot: z₀ = 0, c = pixel
        zx = 0.0f; zy = 0.0f;
        jx = cx;   jy = cy;

        // Early bailout: main cardioid and period-2 bulb
        float q = (cx - 0.25f) * (cx - 0.25f) + cy * cy;
        if (q * (q + (cx - 0.25f)) < 0.25f * cy * cy) {
            output.write(float4(0, 0, 0, 1), gid);
            return;
        }
        float bx = cx + 1.0f;
        if (bx * bx + cy * cy < 0.0625f) {
            output.write(float4(0, 0, 0, 1), gid);
            return;
        }
    } else {
        // Julia: z₀ = pixel, c = fixed parameter
        zx = cx; zy = cy;
        jx = p.juliaCX;
        jy = p.juliaCY;
    }

    // Iterate z = z² + c
    int   iter  = 0;
    float zx2   = 0.0f;
    float zy2   = 0.0f;
    float period = 0.0f;
    float pzx   = 0.0f;
    float pzy   = 0.0f;

    while (iter < p.maxIterations) {
        zx2 = zx * zx;
        zy2 = zy * zy;
        if (zx2 + zy2 > 4.0f) break;

        zy = 2.0f * zx * zy + jy;
        zx = zx2 - zy2 + jx;
        iter++;

        // Cycle detection (periodicity check) — marks interior points quickly
        if (zx == pzx && zy == pzy) { iter = p.maxIterations; break; }
        period += 1.0f;
        if (period >= 20.0f) { period = 0.0f; pzx = zx; pzy = zy; }
    }

    float4 color;
    if (iter >= p.maxIterations) {
        color = float4(0.0f, 0.0f, 0.0f, 1.0f);
    } else {
        // Smooth (continuous) colouring — eliminates iteration banding
        float log_zn = log(zx2 + zy2) * 0.5f;
        float nu     = log(log_zn / log(2.0f)) / log(2.0f);
        float smooth = float(iter) + 1.0f - nu;

        float t = fmod(smooth / p.colorCycleLength + p.colorOffset, 1.0f);
        if (t < 0.0f) t += 1.0f;

        float3 rgb = paletteColor(t, p.paletteIndex);
        color = float4(rgb, 1.0f);
    }

    output.write(color, gid);
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: – Display pass (blit fractal texture to drawable)
// ─────────────────────────────────────────────────────────────────────────────

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Fullscreen triangle strip covering NDC [-1,1]²
vertex VertexOut displayVertex(uint vid [[vertex_id]]) {
    const float2 positions[4] = {
        float2(-1, -1), float2( 1, -1),
        float2(-1,  1), float2( 1,  1)
    };
    // UV: Metal textures have origin top-left; flip Y so bottom-left is (0,0)
    const float2 uvs[4] = {
        float2(0, 1), float2(1, 1),
        float2(0, 0), float2(1, 0)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.texCoord = uvs[vid];
    return out;
}

fragment float4 displayFragment(
    VertexOut                    in  [[stage_in]],
    texture2d<float, access::sample> tex [[texture(0)]]
) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    return tex.sample(s, in.texCoord);
}
