// Misaki ASCII camera drawn entirely with the characters of the tagline
// "Arshes - a camera app to create, publish, and shoot with shader".
// Flat cells use a 12-step coverage ramp " ,-isoenuhmA"; edge cells (Sobel
// over cell luminances + non-maximum suppression) use direction-matched
// glyphs (vertical -> iluA, horizontal -> -cem, diagonals -> sabw / ,rpd).
// Luminance-preserving ink (ink = cellColor / coverage) keeps camera tones.
// The tagline itself is rendered on the same cell grid at the bottom-right,
// right-aligned in two lines, with fixed glyphs and fixed white ink.
// Glyphs from misaki_gothic_2nd.bdf (halfwidth 4x8), packed as uint2:
// rows 0-3 in x, rows 4-7 in y (one byte per row, LSB = row 0, bit7 = leftmost pixel).

static const uint2 ISO_GLYPHS[12] = {
    uint2(0x00000000, 0x00000000), // ' ' (0px)
    uint2(0x00000000, 0x00804000), // ',' (2px)
    uint2(0xe0000000, 0x00000000), // '-' (3px)
    uint2(0x40400040, 0x00404040), // 'i' (6px)
    uint2(0x80600000, 0x00c02040), // 's' (7px)
    uint2(0xa0400000, 0x0040a0a0), // 'o' (8px)
    uint2(0xa0400000, 0x006080e0), // 'e' (9px)
    uint2(0xa0c00000, 0x00a0a0a0), // 'n' (10px)
    uint2(0xa0a00000, 0x00e0a0a0), // 'u' (11px)
    uint2(0xa0c08080, 0x00a0a0a0), // 'h' (12px)
    uint2(0xe0c00000, 0x00a0e0e0), // 'm' (13px)
    uint2(0xa0a0a040, 0x00a0a0e0), // 'A' (14px)
};
static const float ISO_COVERAGE[12] = { 0.0000, 0.1429, 0.2143, 0.4286, 0.5000, 0.5714, 0.6429, 0.7143, 0.7857, 0.8571, 0.9286, 1.0000 };

// 4 direction rows (H, \, V, /) x 4 tone levels
static const uint2 DIR_GLYPHS[16] = {
    // H: -cem (3/7/9/13px)
    uint2(0xe0000000, 0x00000000), uint2(0x80600000, 0x00608080), uint2(0xa0400000, 0x006080e0), uint2(0xe0c00000, 0x00a0e0e0),
    // D1: sabw (7/9/12/12px)
    uint2(0x80600000, 0x00c02040), uint2(0x20c00000, 0x0060a060), uint2(0xa0c08080, 0x00c0a0a0), uint2(0xa0a00000, 0x00a0e0e0),
    // V: iluA (6/8/11/14px)
    uint2(0x40400040, 0x00404040), uint2(0x404040c0, 0x00404040), uint2(0xa0a00000, 0x00e0a0a0), uint2(0xa0a0a040, 0x00a0a0e0),
    // D2: ,rpd (2/7/9/12px)
    uint2(0x00000000, 0x00804000), uint2(0xc0a00000, 0x00808080), uint2(0xa0c00000, 0x0080c0a0), uint2(0xa0602020, 0x0060a0a0),
};
static const float DIR_COVERAGE[16] = { 0.2143, 0.5000, 0.6429, 0.9286, 0.5000, 0.6429, 0.8571, 0.8571, 0.4286, 0.5714, 0.7857, 1.0000, 0.1429, 0.5000, 0.6429, 0.8571 };

// credit: "Arshes - a camera app to create," (32) + "publish, and shoot with shader" (30)
static const int CREDIT_LEN1 = 32;
static const int CREDIT_LEN2 = 30;
static const uint2 CREDIT[62] = {
    uint2(0xa0a0a040, 0x00a0a0e0), // 'A'
    uint2(0xc0a00000, 0x00808080), // 'r'
    uint2(0x80600000, 0x00c02040), // 's'
    uint2(0xa0c08080, 0x00a0a0a0), // 'h'
    uint2(0xa0400000, 0x006080e0), // 'e'
    uint2(0x80600000, 0x00c02040), // 's'
    uint2(0x00000000, 0x00000000), // ' '
    uint2(0xe0000000, 0x00000000), // '-'
    uint2(0x00000000, 0x00000000), // ' '
    uint2(0x20c00000, 0x0060a060), // 'a'
    uint2(0x00000000, 0x00000000), // ' '
    uint2(0x80600000, 0x00608080), // 'c'
    uint2(0x20c00000, 0x0060a060), // 'a'
    uint2(0xe0c00000, 0x00a0e0e0), // 'm'
    uint2(0xa0400000, 0x006080e0), // 'e'
    uint2(0xc0a00000, 0x00808080), // 'r'
    uint2(0x20c00000, 0x0060a060), // 'a'
    uint2(0x00000000, 0x00000000), // ' '
    uint2(0x20c00000, 0x0060a060), // 'a'
    uint2(0xa0c00000, 0x0080c0a0), // 'p'
    uint2(0xa0c00000, 0x0080c0a0), // 'p'
    uint2(0x00000000, 0x00000000), // ' '
    uint2(0x40e04000, 0x00604040), // 't'
    uint2(0xa0400000, 0x0040a0a0), // 'o'
    uint2(0x00000000, 0x00000000), // ' '
    uint2(0x80600000, 0x00608080), // 'c'
    uint2(0xc0a00000, 0x00808080), // 'r'
    uint2(0xa0400000, 0x006080e0), // 'e'
    uint2(0x20c00000, 0x0060a060), // 'a'
    uint2(0x40e04000, 0x00604040), // 't'
    uint2(0xa0400000, 0x006080e0), // 'e'
    uint2(0x00000000, 0x00804000), // ','
    uint2(0xa0c00000, 0x0080c0a0), // 'p'
    uint2(0xa0a00000, 0x00e0a0a0), // 'u'
    uint2(0xa0c08080, 0x00c0a0a0), // 'b'
    uint2(0x404040c0, 0x00404040), // 'l'
    uint2(0x40400040, 0x00404040), // 'i'
    uint2(0x80600000, 0x00c02040), // 's'
    uint2(0xa0c08080, 0x00a0a0a0), // 'h'
    uint2(0x00000000, 0x00804000), // ','
    uint2(0x00000000, 0x00000000), // ' '
    uint2(0x20c00000, 0x0060a060), // 'a'
    uint2(0xa0c00000, 0x00a0a0a0), // 'n'
    uint2(0xa0602020, 0x0060a0a0), // 'd'
    uint2(0x00000000, 0x00000000), // ' '
    uint2(0x80600000, 0x00c02040), // 's'
    uint2(0xa0c08080, 0x00a0a0a0), // 'h'
    uint2(0xa0400000, 0x0040a0a0), // 'o'
    uint2(0xa0400000, 0x0040a0a0), // 'o'
    uint2(0x40e04000, 0x00604040), // 't'
    uint2(0x00000000, 0x00000000), // ' '
    uint2(0xa0a00000, 0x00a0e0e0), // 'w'
    uint2(0x40400040, 0x00404040), // 'i'
    uint2(0x40e04000, 0x00604040), // 't'
    uint2(0xa0c08080, 0x00a0a0a0), // 'h'
    uint2(0x00000000, 0x00000000), // ' '
    uint2(0x80600000, 0x00c02040), // 's'
    uint2(0xa0c08080, 0x00a0a0a0), // 'h'
    uint2(0x20c00000, 0x0060a060), // 'a'
    uint2(0xa0602020, 0x0060a0a0), // 'd'
    uint2(0xa0400000, 0x006080e0), // 'e'
    uint2(0xc0a00000, 0x00808080), // 'r'
};

uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform SamplerState sampler;

[range(1.0, 8.0, 4.0)]
uniform float cellScale;

static const float EDGE_THRESHOLD = 0.35;

[toggle(true)]
uniform bool useCameraColor;

[rgb(0.9, 0.9, 0.85)]
uniform float3 inkColor;

[rgb(0.02, 0.02, 0.03)]
uniform float3 paperColor;

float luminance(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

static const float PI = 3.14159265;

float glyphBit(uint2 g, int2 p) {
    uint row = p.y < 4 ? (g.x >> (p.y * 8)) & 0xFF : (g.y >> ((p.y - 4) * 8)) & 0xFF;
    return float((row >> (7 - p.x)) & 1);
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

    // one shared cell grid (halfwidth 4x8 cells) for both effect and credit
    float scale = floor(cellScale);
    float2 cell = float2(4.0, 8.0) * scale;
    float2 cellId = floor(pixel / cell);
    float2 cellUV = (cellId + 0.5) * cell / resolution;
    int2 p = int2(floor(pixel / scale)) % int2(4, 8);

    // credit: two right-aligned lines above a 1-cell bottom/right margin,
    // rendered exactly like effect cells but with fixed glyphs and white ink
    int2 numCells = int2(floor(resolution / cell));
    int2 c = int2(cellId);
    int row1 = numCells.y - 4, row2 = numCells.y - 2; // one blank row between lines
    if (c.y == row1 || c.y == row2) {
        int len = c.y == row1 ? CREDIT_LEN1 : CREDIT_LEN2;
        int start = numCells.x - 1 - len;
        int offset = c.y == row1 ? 0 : CREDIT_LEN1;
        int at = c.x - start;
        if (at >= 0 && at < len) {
            float on = glyphBit(CREDIT[offset + at], p);
            return float4(lerp(paperColor, float3(1.0, 1.0, 1.0), on), 1.0);
        }
    }

    // --- ASCII effect ---
    float2 q = cell * 0.25 / resolution;
    float3 col = cameraTex.SampleLevel(sampler, cellUV + float2(-q.x, -q.y), 0)
               + cameraTex.SampleLevel(sampler, cellUV + float2( q.x, -q.y), 0)
               + cameraTex.SampleLevel(sampler, cellUV + float2(-q.x,  q.y), 0)
               + cameraTex.SampleLevel(sampler, cellUV + float2( q.x,  q.y), 0);
    col *= 0.25;

    float lum = saturate(luminance(col));
    float perceptual = pow(lum, 1.0 / 2.2);

    // structure: edge cells (with non-maximum suppression) take direction-
    // matched glyphs, flat cells take the coverage ramp
    float2 grad = cellGrad(cellId, cell);
    float mag = length(grad);
    bool isEdge = mag > EDGE_THRESHOLD;
    if (isEdge) {
        float2 nd = float2(round(grad.x / mag), round(grad.y / mag));
        isEdge = mag >= length(cellGrad(cellId + nd, cell)) && mag >= length(cellGrad(cellId - nd, cell));
    }

    uint2 g;
    float coverage;
    if (isEdge) {
        float2 tang = float2(-grad.y, grad.x);
        if (tang.y < 0.0) {
            tang = -tang;
        }
        float ang = atan2(tang.y, tang.x);
        int bin = int(floor(ang / PI * 4.0 + 0.5)) % 4; // 0:H 1:"\" 2:V 3:"/"
        int level = clamp(int(perceptual * 4.0), 0, 3);
        g = DIR_GLYPHS[bin * 4 + level];
        coverage = DIR_COVERAGE[bin * 4 + level];
    } else {
        int idx = clamp(int(perceptual * 12.0), 0, 11);
        g = ISO_GLYPHS[idx];
        coverage = ISO_COVERAGE[idx];
    }

    float on = glyphBit(g, p);

    // luminance-preserving ink: coverage * ink == cell color
    float3 cellCol = useCameraColor ? col : inkColor * lum;
    float3 ink = saturate(cellCol / max(coverage, 1e-3));
    return float4(lerp(paperColor, ink, on), 1.0);
}
