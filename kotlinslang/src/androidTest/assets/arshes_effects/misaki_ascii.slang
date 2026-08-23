// Misaki font ASCII art (halfwidth 4x8 alphanumeric glyphs).
// 18-step ramp " .:-~%=+o*78O@BH#W" whose pixel coverage increases by exactly
// 1px per step (0-17px) — a complete ladder thanks to the punctuation glyphs.
// Luminance-preserving tone model (linear space):
//   cell average = coverage * ink, so ink = cellColor / coverage.
// The area quantization cancels out exactly and the image keeps the camera's
// tonal balance; the glyph pattern only redistributes light inside the cell.
// Coverage is normalized to the densest glyph ('M', 17/32 of the cell), which
// costs a uniform x0.53 exposure — compensate with inkBoost or the app filter.
// Glyphs from misaki_gothic_2nd.bdf, packed as uint2:
// rows 0-3 in x, rows 4-7 in y (one byte per row, LSB = row 0, bit7 = leftmost pixel).
static const uint2 GLYPHS[18] = {
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
// pixel coverage of each glyph, normalized to the densest ('W', 17px)
static const float COVERAGE[18] = { 0.0000, 0.0588, 0.1176, 0.1765, 0.2353, 0.2941, 0.3529, 0.4118, 0.4706, 0.5294, 0.5882, 0.6471, 0.7059, 0.7647, 0.8235, 0.8824, 0.9412, 1.0000 };

uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform SamplerState sampler;

[range(1.0, 8.0, 3.0)]
uniform float cellScale;

[range(1.0, 3.0, 1.0)]
uniform float inkBoost;

[toggle(false)]
uniform bool invert;

[toggle(true)]
uniform bool useCameraColor;

[rgb(0.9, 0.9, 0.85)]
uniform float3 inkColor;

[rgb(0.02, 0.02, 0.03)]
uniform float3 paperColor;

float luminance(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float scale = floor(cellScale);
    float2 cell = float2(4.0, 8.0) * scale;
    float2 pixel = uv * resolution;
    float2 cellId = floor(pixel / cell);
    float2 cellUV = (cellId + 0.5) * cell / resolution;

    // average color over the cell (2x2 taps)
    float2 q = cell * 0.25 / resolution;
    float3 col = cameraTex.SampleLevel(sampler, cellUV + float2(-q.x, -q.y), 0)
               + cameraTex.SampleLevel(sampler, cellUV + float2( q.x, -q.y), 0)
               + cameraTex.SampleLevel(sampler, cellUV + float2(-q.x,  q.y), 0)
               + cameraTex.SampleLevel(sampler, cellUV + float2( q.x,  q.y), 0);
    col *= 0.25;

    float lum = saturate(luminance(col));
    if (invert) {
        lum = 1.0 - lum;
    }

    // pick the glyph on a perceptual (gamma) axis so dark tones get their share of steps
    float perceptual = pow(lum, 1.0 / 2.2);
    int idx = clamp(int(perceptual * 18.0), 0, 17);
    uint2 g = GLYPHS[idx];

    // local pixel inside the 4x8 glyph
    int2 p = int2(floor(pixel / scale)) % int2(4, 8);
    uint row = p.y < 4 ? (g.x >> (p.y * 8)) & 0xFF : (g.y >> ((p.y - 4) * 8)) & 0xFF;
    float on = float((row >> (7 - p.x)) & 1);

    // spread the cell's light over the glyph area: coverage * ink == cell color
    float3 cellCol = useCameraColor ? col : inkColor * lum;
    float3 ink = saturate(cellCol / max(COVERAGE[idx], 1e-3) * inkBoost);
    return float4(lerp(paperColor, ink, on), 1.0);
}
