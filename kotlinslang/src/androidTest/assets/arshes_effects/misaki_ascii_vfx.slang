// Partial ASCII: the camera image stays intact except where the region mask
// fires (high saturation by default) — there the image is rebuilt as full
// ASCII fill: edge cells (non-maximum suppressed Sobel) use direction-matched
// glyphs, flat cells use the isotropic coverage ramp, with luminance-
// preserving ink (ink = cellColor / coverage) so the fill keeps the camera's
// tones. Region mask = weighted mix of saturation / highlights / screen ring.
// Glyphs from misaki_gothic_2nd.bdf (halfwidth 4x8), packed as uint2:
// rows 0-3 in x, rows 4-7 in y (one byte per row, LSB = row 0, bit7 = leftmost pixel).

// 4 direction rows (H, \, V, /) x 6 tone levels
static const uint2 DIR_GLYPHS[24] = {
    // H : -ﾆ=ﾐﾗﾖ (3/5/6/8/10/12px)
    uint2(0xe0000000, 0x00000000), uint2(0x00006000, 0x00e00000), uint2(0x00e00000, 0x000000e0), uint2(0x6000e000, 0x00e00000), uint2(0xe000e000, 0x00c02020), uint2(0xe020e000, 0x00e02020),
    // D1: \~sﾏﾀ6 (3/4/7/9/10/11px)
    uint2(0x40800000, 0x00000020), uint2(0x60c00000, 0x00000000), uint2(0x80600000, 0x00c02040), uint2(0x2020e000, 0x002040c0), uint2(0x60a06040, 0x00804020), uint2(0xc080a040, 0x0040a0a0),
    // V : "i|lﾘﾊ (4/6/7/8/11/12px)
    uint2(0x0000a0a0, 0x00000000), uint2(0x40400040, 0x00404040), uint2(0x40404040, 0x00404040), uint2(0x404040c0, 0x00404040), uint2(0xa0a0a0a0, 0x00402020), uint2(0xa0a02040, 0x00a0a0a0),
    // D2: /%ﾉｸｿﾁ (3/5/7/9/10/10px)
    uint2(0x40200000, 0x00000080), uint2(0x40208000, 0x00002080), uint2(0x20202020, 0x00804020), uint2(0x20a06040, 0x00804020), uint2(0x206060a0, 0x00804020), uint2(0xe040c020, 0x00804040),
};
static const float DIR_COVERAGE[24] = { 0.1765, 0.2941, 0.3529, 0.4706, 0.5882, 0.7059, 0.1765, 0.2353, 0.4118, 0.5294, 0.5882, 0.6471, 0.2353, 0.3529, 0.4118, 0.4706, 0.6471, 0.7059, 0.1765, 0.2941, 0.4118, 0.5294, 0.5882, 0.5882 };

// isotropic coverage ramp " .:-~%=+o*78O@BH#W" for flat (non-edge) cells
static const uint2 ISO_GLYPHS[18] = {
    uint2(0x00000000, 0x00000000), // ' ' (0px)
    uint2(0x00000000, 0x00400000), // '.' (1px)
    uint2(0x00400000, 0x00004000), // ':' (2px)
    uint2(0xe0000000, 0x00000000), // '-' (3px)
    uint2(0x60c00000, 0x00000000), // '~' (4px)
    uint2(0x40208000, 0x00002080), // '%' (5px)
    uint2(0x00e00000, 0x000000e0), // '=' (6px)
    uint2(0xe0404000, 0x00004040), // '+' (7px)
    uint2(0xa0400000, 0x0040a0a0), // 'o' (8px)
    uint2(0xe040a000, 0x0000a040), // '*' (9px)
    uint2(0x4020a0e0, 0x00404040), // '7' (10px)
    uint2(0x40a0a040, 0x0040a0a0), // '8' (11px)
    uint2(0xa0a0a040, 0x0040a0a0), // 'O' (12px)
    uint2(0xa0e0a040, 0x006080c0), // '@' (13px)
    uint2(0xc0a0a0c0, 0x00c0a0a0), // 'B' (14px)
    uint2(0xe0a0a0a0, 0x00a0a0a0), // 'H' (15px)
    uint2(0xa0a0e0a0, 0x00a0e0a0), // '#' (16px)
    uint2(0xe0a0a0a0, 0x00a0e0e0), // 'W' (17px)
};
static const float ISO_COVERAGE[18] = { 0.0000, 0.0588, 0.1176, 0.1765, 0.2353, 0.2941, 0.3529, 0.4118, 0.4706, 0.5294, 0.5882, 0.6471, 0.7059, 0.7647, 0.8235, 0.8824, 0.9412, 1.0000 };

uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform SamplerState sampler;

[range(1.0, 8.0, 3.0)]
uniform float cellScale;

[range(0.0, 1.0, 0.3)]
uniform float edgeThreshold;

[range(0.2, 1.0, 0.6)]
uniform float strokeWeight;

// region mask weights
[range(0.0, 1.0, 1.0)]
uniform float satWeight;

[range(0.0, 1.0, 0.0)]
uniform float lumWeight;

[range(0.0, 1.0, 0.0)]
uniform float ringWeight;

// saturation above which a cell joins the ASCII region
[range(0.0, 1.0, 0.35)]
uniform float satThreshold;

// distance from screen center (aspect-corrected, 0.5 = halfway) where the ring starts
[range(0.2, 0.9, 0.45)]
uniform float ringRadius;

[toggle(true)]
uniform bool useCameraColor;

[rgb(0.95, 0.95, 0.9)]
uniform float3 inkColor;

float luminance(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

static const float PI = 3.14159265;

float3 cellColor(float2 cellId, float2 cell) {
    float2 cellUV = (cellId + 0.5) * cell / resolution;
    float2 q = cell * 0.25 / resolution;
    float3 col = cameraTex.SampleLevel(sampler, cellUV + float2(-q.x, -q.y), 0)
               + cameraTex.SampleLevel(sampler, cellUV + float2( q.x, -q.y), 0)
               + cameraTex.SampleLevel(sampler, cellUV + float2(-q.x,  q.y), 0)
               + cameraTex.SampleLevel(sampler, cellUV + float2( q.x,  q.y), 0);
    return col * 0.25;
}

float cellLumP(float2 cellId, float2 cell) {
    float2 cellUV = (cellId + 0.5) * cell / resolution;
    return pow(saturate(luminance(cameraTex.SampleLevel(sampler, cellUV, 0))), 1.0 / 2.2);
}

float2 cellGrad(float2 cellId, float2 cell) {
    float tl = cellLumP(cellId + float2(-1, -1), cell), t = cellLumP(cellId + float2(0, -1), cell), tr = cellLumP(cellId + float2(1, -1), cell);
    float l  = cellLumP(cellId + float2(-1,  0), cell),                                              r  = cellLumP(cellId + float2(1,  0), cell);
    float bl = cellLumP(cellId + float2(-1,  1), cell), b = cellLumP(cellId + float2(0,  1), cell), br = cellLumP(cellId + float2(1,  1), cell);
    return float2((tr + 2.0 * r + br) - (tl + 2.0 * l + bl),
                  (bl + 2.0 * b + br) - (tl + 2.0 * t + tr));
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float2 pixel = uv * resolution;
    float3 camera = cameraTex.Sample(sampler, uv);

    float scale = floor(cellScale);
    float2 cell = float2(4.0, 8.0) * scale;
    float2 cellId = floor(pixel / cell);

    // --- region mask (per cell, so whole glyphs fade together) ---
    float3 col = cellColor(cellId, cell);
    float lum = saturate(luminance(col));
    // saturation belongs to the perceptual (gamma) domain — computing it on
    // linear RGB overestimates chroma, e.g. warm room light reads as vivid
    float3 srgb = pow(saturate(col), 1.0 / 2.2);
    float mx = max(srgb.r, max(srgb.g, srgb.b));
    float sat = mx > 1e-4 ? (mx - min(srgb.r, min(srgb.g, srgb.b))) / mx : 0.0;

    float2 cellUV = (cellId + 0.5) * cell / resolution;
    float2 d = (cellUV - 0.5) * float2(resolution.x / resolution.y, 1.0);

    // dark cells have unreliable saturation — fade them out of the sat mask
    float satM = smoothstep(satThreshold, satThreshold + 0.2, sat) * smoothstep(0.02, 0.08, lum);
    float lumM = smoothstep(0.55, 0.8, lum);
    float ringM = smoothstep(ringRadius, ringRadius + 0.12, length(d));
    float region = saturate(satWeight * satM + lumWeight * lumM + ringWeight * ringM);
    if (region < 0.01) {
        return float4(camera, 1.0);
    }

    // --- structure: edge cells (with non-maximum suppression) take
    // direction-matched glyphs, flat cells take the coverage ramp fill ---
    float2 grad = cellGrad(cellId, cell);
    float mag = length(grad);
    bool isEdge = mag > edgeThreshold;
    if (isEdge) {
        float2 nd = float2(round(grad.x / mag), round(grad.y / mag));
        isEdge = mag >= length(cellGrad(cellId + nd, cell)) && mag >= length(cellGrad(cellId - nd, cell));
    }

    float perceptual = pow(lum, 1.0 / 2.2);
    uint2 g;
    float coverage;
    if (isEdge) {
        float2 tang = float2(-grad.y, grad.x);
        if (tang.y < 0.0) {
            tang = -tang;
        }
        float ang = atan2(tang.y, tang.x);
        int bin = int(floor(ang / PI * 4.0 + 0.5)) % 4; // 0:H 1:"\" 2:V 3:"/"
        int level = clamp(int(perceptual * 6.0 * strokeWeight), 0, 5);
        g = DIR_GLYPHS[bin * 6 + level];
        coverage = DIR_COVERAGE[bin * 6 + level];
    } else {
        int idx = clamp(int(perceptual * 18.0), 0, 17);
        g = ISO_GLYPHS[idx];
        coverage = ISO_COVERAGE[idx];
    }

    int2 p = int2(floor(pixel / scale)) % int2(4, 8);
    uint row = p.y < 4 ? (g.x >> (p.y * 8)) & 0xFF : (g.y >> ((p.y - 4) * 8)) & 0xFF;
    float on = float((row >> (7 - p.x)) & 1);

    // overlay: glyphs draw directly on the camera image (no paper backdrop).
    // ink = cellColor / coverage keeps the local hue but lifts brightness in
    // proportion to glyph sparsity, so text stays readable over the photo.
    float3 cellCol = useCameraColor ? col : inkColor * lum;
    float3 ink = saturate(cellCol / max(coverage, 1e-3));
    return float4(lerp(camera, ink, on * region), 1.0);
}
