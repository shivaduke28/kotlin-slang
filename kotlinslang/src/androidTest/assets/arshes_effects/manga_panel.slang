// Manga panel: crops the camera into a comic frame on paper.
// Inside the frame the image is reduced to a 4-level manga tone
// (black / two screentones / white) with ink contour lines.
// Under the frame: "ARSHES" credits in Misaki pixel type; beside it,
// a hand-drawn speech bubble with a lightning bolt.
// 
// Inspired by
// 初星学園 「サンフェーデッド」Official Music Video (HATSUBOSHI GAKUEN - SUNFADED)
// https://www.youtube.com/watch?v=XLwmEuM0dIw

uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform SamplerState sampler;
uniform Texture2D<float> blueNoiseTex;

// touch to move the panel (defaults to screen center until touched)
uniform float3 touch;
uniform int frame;

// panel center in screen UV, updated by computeMain while touching
[size(1)]
RWStructuredBuffer<float2> panelCenter;

// ---- panel shape ----------------------------------------------------------

// panel width / height (default 16:9, up to cinemascope 2.35)
[range(0.425, 2.35, 1.7778)]
uniform float aspect;

// panel short side relative to min screen dimension; the panel grows
// from a 1:1 square, stretching horizontally (aspect > 1) or
// vertically (aspect < 1) while the short side stays fixed
[range(0.1, 1, 0.3)]
uniform float scale;

// all relative to min screen dimension
static const float cornerRadius = 0.01;
static const float lineWidth = 0.006;
// how much the ink flow thins a stroke in places
static const float inkThinning = 0.6;
// ink darkness of every drawn mark
static const float inkColor = 0.02;

// ---- tone -----------------------------------------------------------------

// luma below this -> solid black
[range(0, 1, 0.25)]
uniform float blackPoint;

// luma above this -> paper white
[range(0, 1, 0.65)]
uniform float whitePoint;

// number of screentone grays between black and white
// 0: black & white only, 1: grayLight only, 2: grayDark + grayLight
[range(0, 2, 2)]
uniform int grayCount;

// screentone dot density of the darker gray
[range(0, 1, 0.35)]
uniform float grayDark;

// screentone dot density of the lighter gray
[range(0, 1, 0.65)]
uniform float grayLight;

// contour line sensitivity (0 = no lines)
[range(0, 4, 1.5)]
uniform float edgeGain;

// ---- speech bubble --------------------------------------------------------

// bubble center relative to panel center, in units of panel size
[range(-1, 1, 0.7)]
uniform float bubbleX;

[range(-1, 1, -0.28)]
uniform float bubbleY;

// ellipse height relative to min screen dimension (0 hides the bubble)
[range(0, 0.5, 0.16)]
uniform float bubbleSize;

// ellipse width / height (< 1: tall bubble)
static const float bubbleAspect = 0.72;

// hand-drawn pen wobble of the bubble outline, relative to min screen dimension
static const float bubbleWobble = 0.001;

// lightning bolt size relative to the bubble's vertical radius
static const float boltSize = 0.4;

// bolt shape: zigzag hexagon, decomposed into 4 triangles below
static const float2 boltA = float2(0.28, -0.52);
static const float2 boltB = float2(-0.38, 0.14);
static const float2 boltC = float2(-0.02, 0.14);
static const float2 boltD = float2(-0.28, 0.52);
static const float2 boltE = float2(0.38, -0.14);
static const float2 boltF = float2(0.02, -0.14);

// ---- credits --------------------------------------------------------------

// Font credit:
//   美咲ゴシック第2 (Misaki Gothic 2nd)
//   Copyright (C) 2002-2021 Num Kadoma
//   https://littlelimit.net/misaki.htm
// All text uses its halfwidth 4x8 glyphs (extracted from
// misaki_gothic_2nd.bdf): one uint per char, bit index = row * 4 + col,
// row 0 = top. Glyphs advance 4 columns; letter spacing is built into
// the cell.
static const int captionLen = 6;
static const uint captionGlyphs[6] = {
  0x05575552, 0x05553553, 0x02542152, 0x05557555, 0x07113117, 0x02542152, // ARSHES
};
static const int subtitle1Len = 37;
static const uint subtitle1Glyphs[37] = {
  0x06564300, 0x05555300, 0x00000000, 0x02222202, 0x02555552, 0x02542152, 0x00000000, 0x06111600, 0x06564300, 0x05777300, // an iOS cam
  0x06175200, 0x01113500, 0x06564300, 0x00000000, 0x06564300, 0x01355300, 0x01355300, 0x00000000, 0x06222720, 0x02555200, // era app to
  0x00000000, 0x06111600, 0x01113500, 0x06175200, 0x06564300, 0x06222720, 0x06175200, 0x01200000, 0x00000000, 0x01355300, //  create, p
  0x07555500, 0x03555311, 0x02222223, 0x02222202, 0x03421600, 0x05555311, 0x01200000, // ublish,
};
static const int subtitle2Len = 21;
static const uint subtitle2Glyphs[21] = {
  0x06564300, 0x05555300, 0x06555644, 0x00000000, 0x03421600, 0x05555311, 0x02555200, 0x02555200, 0x06222720, 0x00000000, // and shoot
  0x05775500, 0x02222202, 0x06222720, 0x05555311, 0x00000000, 0x03421600, 0x05555311, 0x06564300, 0x06555644, 0x06175200, // with shade
  0x01113500, // r
};

// base glyph pixel size relative to min screen dimension (= subtitle scale
// before subtitleScale; the title uses captionScale of it)
[range(0.002, 0.02, 0.005)]
uniform float captionPx;

// title glyph pixel size relative to captionPx
static const float captionScale = 0.7;

// subtitle glyph pixel size relative to captionPx
static const float subtitleScale = 0.32;

// ---- noise & SDF helpers --------------------------------------------------

float hash21(float2 p) {
  p = frac(p * float2(123.34, 345.45));
  p += dot(p, p + 34.345);
  return frac(p.x * p.y);
}

float valueNoise(float2 p) {
  float2 i = floor(p);
  float2 f = frac(p);
  float2 u = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + float2(1, 0));
  float c = hash21(i + float2(0, 1));
  float d = hash21(i + float2(1, 1));
  return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

float sdRoundBox(float2 p, float2 halfSize, float r) {
  float2 q = abs(p) - halfSize + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float sdEllipseApprox(float2 p, float2 r) {
  float k1 = length(p / r);
  float k2 = length(p / (r * r));
  return k1 * (k1 - 1.0) / max(k2, 1e-6);
}

float sdTriangle(float2 p, float2 a, float2 b, float2 c) {
  float2 e0 = b - a, e1 = c - b, e2 = a - c;
  float2 v0 = p - a, v1 = p - b, v2 = p - c;
  float2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
  float2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
  float2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
  float s = sign(e0.x * e2.y - e0.y * e2.x);
  float2 d = min(min(float2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                     float2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                     float2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
  return -sqrt(d.x) * sign(d.y);
}

// ink alpha of a stroke along d = 0: width w, occasionally thinned by
// the pen flow (thinNoise is a valueNoise sample; vary its seed per stroke)
float inkStroke(float d, float w, float thinNoise) {
  w *= 1.0 - inkThinning * 0.7 * smoothstep(0.55, 0.85, thinNoise);
  return 1.0 - smoothstep(w * 0.5 - 1.0, w * 0.5 + 1.5, abs(d));
}

// ---- manga tone -----------------------------------------------------------

float perceptualLuma(float2 uv) {
  float3 c = cameraTex.Sample(sampler, uv);
  float luma = dot(c, float3(0.2126, 0.7152, 0.0722));
  return pow(saturate(luma), 1.0 / 2.2);
}

// manga tone: black / dark gray / light gray / white.
// blackPoint/whitePoint set where black ends and white begins;
// the black and white bands never move. With grayCount 1 the two
// middle bands share grayLight, with 0 they become white.
float mangaTone(float g) {
  float t = smoothstep(blackPoint, whitePoint, g);
  if (t < 0.25) return 0.0;
  if (t >= 0.75 || grayCount == 0) return 1.0;
  if (grayCount == 1) return grayLight;
  return t < 0.5 ? grayDark : grayLight;
}

// contour lines from the luma gradient (central difference)
float contourEdge(float2 uv) {
  float2 texel = 3.5 / resolution;
  float gx = perceptualLuma(uv + float2(texel.x, 0)) - perceptualLuma(uv - float2(texel.x, 0));
  float gy = perceptualLuma(uv + float2(0, texel.y)) - perceptualLuma(uv - float2(0, texel.y));
  return smoothstep(0.5, 0.9, length(float2(gx, gy)) * 4.0 * edgeGain);
}

// ---- text -----------------------------------------------------------------

// coverage of a glyph run at p (in glyph-pixel units, origin = top-left)
float textMask<let N : int>(uint glyphs[N], float2 p) {
  if (p.x < 0.0 || p.y < 0.0 || p.y >= 8.0) return 0.0;
  int col = int(p.x);
  int ci = col / 4;
  if (ci >= N) return 0.0;
  uint bit = uint(int(p.y) * 4 + col % 4);
  return ((glyphs[ci] >> bit) & 1u) != 0u ? 1.0 : 0.0;
}

// title + two subtitle lines, all right-aligned to rightEdge,
// starting below `top` (the panel's bottom border)
float creditsMask(float2 px, float rightEdge, float top, float minDim) {
  float basePx = captionPx * minDim;
  float capPx = basePx * captionScale;
  float subPx = basePx * subtitleScale;

  float2 capOrigin = float2(rightEdge - float(captionLen * 4) * capPx,
                            top + basePx * 7.0);
  float m = textMask(captionGlyphs, (px - capOrigin) / capPx);

  float2 sub1Origin = float2(rightEdge - float(subtitle1Len * 4) * subPx,
                             capOrigin.y + 8.0 * capPx + 8.0 * subPx);
  m = max(m, textMask(subtitle1Glyphs, (px - sub1Origin) / subPx));

  float2 sub2Origin = float2(rightEdge - float(subtitle2Len * 4) * subPx,
                             sub1Origin.y + 9.0 * subPx);
  return max(m, textMask(subtitle2Glyphs, (px - sub2Origin) / subPx));
}

// ---- speech bubble --------------------------------------------------------

void drawBubble(inout float col, float2 px, float2 bc, float paperTone, float minDim) {
  float2 br = float2(bubbleAspect, 1.0) * bubbleSize * 0.5 * minDim;
  float db = sdEllipseApprox(px - bc, br);
  // hand-drawn pen: the outline path itself wanders a little
  db += (valueNoise(px / minDim * 25.0) - 0.5) * 2.0 * bubbleWobble * minDim;
  if (db < 0.0) col = paperTone;

  float ink = inkStroke(db, lineWidth * minDim, valueNoise(px / minDim * 12.0 + 37.0));
  // pen strokes don't quite close: gaps where one stroke ends and
  // the next begins (top-right and bottom-left, like two arcs)
  float ang = atan2((px.y - bc.y) / br.y, (px.x - bc.x) / br.x);
  float g1 = abs(atan2(sin(ang + 0.9), cos(ang + 0.9)));
  float g2 = abs(atan2(sin(ang - 2.5), cos(ang - 2.5)));
  ink *= smoothstep(0.04, 0.13, g1) * smoothstep(0.03, 0.10, g2);
  col = lerp(col, inkColor, ink);

  // lightning bolt inside the bubble (zigzag hexagon, 4 triangles)
  if (db < 0.0) {
    float boltScale = br.y * boltSize;
    float2 bp = (px - bc) / boltScale;
    float dbolt = min(min(sdTriangle(bp, boltC, boltD, boltE), sdTriangle(bp, boltF, boltA, boltB)),
                      min(sdTriangle(bp, boltB, boltC, boltE), sdTriangle(bp, boltB, boltE, boltF)));
    // fatten a touch to blunt the sharp tips
    dbolt -= 0.05;
    // rough inked edges, like hand-lettered manga type
    dbolt += (valueNoise(px / minDim * 260.0) - 0.5) * 2.0 * (1.2 / boltScale);
    col = lerp(col, inkColor, 1.0 - smoothstep(0.0, 1.0 / boltScale, dbolt));
  }
}

// ---- main -----------------------------------------------------------------

[dispatch(1, 1, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
void computeMain(uint3 id : SV_DispatchThreadID) {
  if (frame == 0) {
    panelCenter[0] = float2(0.5, 0.5);
  }
  if (touch.z > 0.5) {
    panelCenter[0] = touch.xy;
  }
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
  float2 px = uv * resolution;
  float minDim = min(resolution.x, resolution.y);
  float2 panelPx = panelCenter[0] * resolution;

  float2 rectSize = scale * minDim * float2(max(aspect, 1.0), max(1.0 / aspect, 1.0));
  float d = sdRoundBox(px - panelPx, rectSize * 0.5, cornerRadius * minDim);

  // paper background with subtle unevenness
  float paperTone = 0.92 + 0.04 * valueNoise(px / minDim * 4.0);
  float col = paperTone;

  // camera image as manga tone, screened by blue noise, inside the panel
  if (d < 0.0) {
    float bn = blueNoiseTex.Load(int3(int(px.x) % 256, int(px.y) % 256, 0));
    float tone = mangaTone(perceptualLuma(uv));
    float bw = min(step(bn, tone), 1.0 - contourEdge(uv));
    col = bw * paperTone;
  }

  // panel border: ruler-drawn line — perfectly straight, but the ink
  // flow occasionally thins the stroke
  float lw = lineWidth * minDim;
  if (abs(d) < lw) {
    float ink = inkStroke(d, lw, valueNoise(px / minDim * 12.0));
    col = lerp(col, inkColor, ink);
  }

  // speech bubble: paper-white ellipse with an inked outline and a bolt
  if (bubbleSize > 0.005) {
    float2 bc = panelPx + float2(bubbleX, bubbleY) * rectSize;
    drawBubble(col, px, bc, paperTone, minDim);
  }

  // credits below the panel, right-aligned to its right edge
  float credits = creditsMask(px, panelPx.x + rectSize.x * 0.5,
                              panelPx.y + rectSize.y * 0.5 + lineWidth * minDim, minDim);
  col = lerp(col, inkColor, credits);

  return float4(col, col, col, 1);
}
