// Misaki font ASCII art that also matches glyph *shape* to the image:
// a Sobel filter over neighboring cell luminances gives the local edge
// tangent; strong edges pick glyphs whose stroke direction agrees
// (vertical edge -> "i|lﾘﾊ, horizontal -> -ﾆ=ﾐﾗﾖ, diagonals -> \~sﾏﾀ6 / /%ﾉｸｿﾁ),
// flat regions fall back to the isotropic coverage ramp " .:-~%=+o*78O@BH#W".
// Direction features were measured offline from the bitmaps (co-occurrence of
// lit pixel pairs along each of the 4 orientations).
// Luminance-preserving: ink = cellColor / coverage, so cell average tone
// equals the camera tone regardless of which glyph is chosen.
// Glyphs from misaki_gothic_2nd.bdf (halfwidth 4x8), packed as uint2:
// rows 0-3 in x, rows 4-7 in y (one byte per row, LSB = row 0, bit7 = leftmost pixel).

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

uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform SamplerState sampler;

[range(1.0, 8.0, 3.0)]
uniform float cellScale;

// Sobel magnitude (in perceptual luminance) above which a cell is "an edge"
[range(0.0, 1.0, 0.35)]
uniform float edgeThreshold;

[range(1.0, 3.0, 1.0)]
uniform float inkBoost;

// line-drawing mode: only edge cells draw glyphs (level = edge strength),
// flat cells stay paper — like structure-based ASCII art
[toggle(true)]
uniform bool edgesOnly;

// scales the glyph density used for strokes: low = airy thin lines ("-/|"),
// high = bold strokes ("ﾖﾊ")
[range(0.2, 1.0, 0.45)]
uniform float strokeWeight;

[toggle(false)]
uniform bool invert;

[toggle(false)]
uniform bool useCameraColor;

[rgb(0.1, 0.1, 0.12)]
uniform float3 inkColor;

[rgb(0.97, 0.96, 0.93)]
uniform float3 paperColor;

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

// perceptual luminance of a neighboring cell (single tap is enough for Sobel)
float cellLumP(float2 cellId, float2 cell) {
    float2 cellUV = (cellId + 0.5) * cell / resolution;
    return pow(saturate(luminance(cameraTex.SampleLevel(sampler, cellUV, 0))), 1.0 / 2.2);
}

// Sobel gradient over the 3x3 neighborhood of cells (screen coords, y down)
float2 cellGrad(float2 cellId, float2 cell) {
    float tl = cellLumP(cellId + float2(-1, -1), cell), t = cellLumP(cellId + float2(0, -1), cell), tr = cellLumP(cellId + float2(1, -1), cell);
    float l  = cellLumP(cellId + float2(-1,  0), cell),                                              r  = cellLumP(cellId + float2(1,  0), cell);
    float bl = cellLumP(cellId + float2(-1,  1), cell), b = cellLumP(cellId + float2(0,  1), cell), br = cellLumP(cellId + float2(1,  1), cell);
    float gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
    float gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
    return float2(gx, gy);
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float scale = floor(cellScale);
    float2 cell = float2(4.0, 8.0) * scale;
    float2 pixel = uv * resolution;
    float2 cellId = floor(pixel / cell);

    float3 col = cellColor(cellId, cell);
    float lum = saturate(luminance(col));
    if (invert) {
        lum = 1.0 - lum;
    }
    float perceptual = pow(lum, 1.0 / 2.2);

    float2 grad = cellGrad(cellId, cell);
    float mag = length(grad);

    // non-maximum suppression: keep only cells whose gradient is a local
    // maximum along the gradient direction, so contours thin to one cell
    bool isEdge = mag > edgeThreshold;
    if (isEdge) {
        float2 nd = float2(round(grad.x / mag), round(grad.y / mag));
        float m1 = length(cellGrad(cellId + nd, cell));
        float m2 = length(cellGrad(cellId - nd, cell));
        isEdge = mag >= m1 && mag >= m2;
    }

    uint2 g;
    float coverage;
    if (isEdge) {
        // edge tangent = gradient rotated 90 degrees
        float2 tang = float2(-grad.y, grad.x);
        if (tang.y < 0.0) {
            tang = -tang;
        }
        float ang = atan2(tang.y, tang.x);          // [0, PI], y down
        int bin = int(floor(ang / PI * 4.0 + 0.5)) % 4; // 0:H 1:"\" 2:V 3:"/"
        // tone mode: level follows cell luminance; line mode: edge strength
        float lv = edgesOnly ? (mag - edgeThreshold) / max(1.0 - edgeThreshold, 1e-3) * strokeWeight : perceptual;
        int level = clamp(int(lv * 6.0), 0, 5);
        g = DIR_GLYPHS[bin * 6 + level];
        coverage = DIR_COVERAGE[bin * 6 + level];
    } else if (edgesOnly) {
        return float4(paperColor, 1.0);
    } else {
        int idx = clamp(int(perceptual * 18.0), 0, 17);
        g = ISO_GLYPHS[idx];
        coverage = ISO_COVERAGE[idx];
    }

    // local pixel inside the 4x8 glyph
    int2 p = int2(floor(pixel / scale)) % int2(4, 8);
    uint row = p.y < 4 ? (g.x >> (p.y * 8)) & 0xFF : (g.y >> ((p.y - 4) * 8)) & 0xFF;
    float on = float((row >> (7 - p.x)) & 1);

    float3 ink;
    if (edgesOnly) {
        // a drawing, not tone reproduction: strokes at full ink
        ink = useCameraColor ? col / max(luminance(col), 1e-4) : inkColor;
    } else {
        // spread the cell's light over the glyph area: coverage * ink == cell color
        float3 cellCol = useCameraColor ? col : inkColor * lum;
        ink = saturate(cellCol / max(coverage, 1e-3) * inkBoost);
    }
    return float4(lerp(paperColor, ink, on), 1.0);
}
