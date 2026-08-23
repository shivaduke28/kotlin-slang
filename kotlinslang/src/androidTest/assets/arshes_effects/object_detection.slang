// Object detection HUD built from established algorithms:
//
// 1. Saliency: multi-scale center-surround contrast, method "AC"
//    (Achanta, Estrada, Wils, Susstrunk, "Salient Region Detection and
//    Segmentation", ICVS 2008). S(x,y) = sum over scales t of
//    || I_blur(x,y) - mean Lab of the window of half-size t around (x,y) ||_2,
//    with window half-sizes GR/2, GR/4, GR/8. Window means are O(1) via an
//    integral image (summed-area table). Distances in CIELab; the center
//    value uses a 5x5 binomial blur for noise robustness (as in the
//    frequency-tuned successor, CVPR 2009).
// 2. Binarization: adaptive threshold Ta proportional to mean saliency
//    (Achanta CVPR 2009, Eq. 9), followed by a morphological opening.
// 3. Region extraction: connected-component labeling (BFS flood fill),
//    bounding box + area per component.
// 4. Tracking: SORT-style (Bewley et al. 2016) — constant-velocity motion
//    model on state [u, v, s, r] (center, area, aspect), greedy IoU
//    association (Bochinski et al. 2017), min-hits / max-age lifecycle.
//    Filter gains are steady-state (alpha-beta), i.e. a fixed-gain Kalman.

uniform float deltaTime;
uniform int frame;
uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform SamplerState sampler;

// --- user parameters ---
[range(0.1, 1.0, 0.7)]
uniform float sensitivity; // scales the adaptive threshold multiplier

[range(1, 16, 10)]
uniform int boxCount; // max number of windows on screen

[range(1, 20, 2)]
uniform int minBoxSize; // min blob area in grid cells

[toggle(true)]
uniform bool showLinks; // connect windows with a minimum spanning tree

[range(0.0, 1.0, 0.0)]
uniform float colorBlend; // 0: center-surround contrast, 1: Lab chroma (vividness), in between: blend

// --- SORT lifecycle / association parameters ---
static const int MIN_HITS = 2;    // consecutive hits before a track is shown
static const int MAX_AGE = 3;     // frames a track may coast unmatched
static const float IOU_MIN = 0.05; // min IoU to associate detection with track
static const float POS_GAIN = 0.45; // steady-state filter position gain
static const float VEL_GAIN = 0.25; // steady-state filter velocity gain
static const float SAL_EMA = 0.5;  // temporal smoothing of the saliency map (1 = off)

// hue-gated connectivity: neighbor cells join a blob only if their a*b* hue
// directions agree, so adjacent vivid objects of different hue split apart
static const float HUE_JOIN_COS = 0.707;   // max hue angle between neighbors (45 deg)
static const float CHROMA_NEUTRAL = 10.0;  // below this chroma, hue is undefined: always join

static const int GR = 64;
static const int NCELL = GR * GR;
static const int MAXDET = 16;
static const int NTRACK = 16;

[size2d(64, 64)]
RWTexture2D<float4> labRW; // CIELab per cell

[size2d(64, 64)]
RWTexture2D<float4> tmpRW; // horizontal blur intermediate

[size2d(64, 64)]
RWTexture2D<float4> blurRW; // 5x5 binomial blurred Lab

[size(4096)]
RWStructuredBuffer<float> salBuf; // saliency per cell

[size(4096)]
RWStructuredBuffer<float4> satBuf; // integral image (summed-area table) of Lab

[size(65)]
RWStructuredBuffer<float> rowSum; // per-row saliency sums; [64] = grand total

[size(4096)]
RWStructuredBuffer<int> cellState; // binary mask / CCL visit state

[size(4096)]
RWStructuredBuffer<int> stackBuf; // morphology temp, then BFS stack

struct Track
{
    float4 posVel;  // u, v, du, dv (uv units, uv/sec)
    float4 sizeVel; // s (area), ds, r (aspect w/h), unused
    float4 meta;    // hits, missFrames, displayAlpha, active
};

[size(16)]
RWStructuredBuffer<Track> tracks;

[size(16)]
RWStructuredBuffer<float4> links; // MST edges: xy -> zw corners (uv)

// compact draw list so the fragment pass only touches visible boxes
[size(17)]
RWStructuredBuffer<float4> hudBoxes; // [0] = (box count, link count, 0, 0); [1..16] rects (uv)

[size(16)]
RWStructuredBuffer<int> hudIds; // original track slot per compacted box (label text)

// --- linear sRGB (D65) -> CIELab ---
float labF(float t)
{
    return (t > 0.008856) ? pow(t, 1.0 / 3.0) : (903.3 * t + 16.0) / 116.0;
}

float3 rgbToLab(float3 c)
{
    // sRGB D65 RGB->XYZ, normalized by white point
    float x = dot(c, float3(0.4124, 0.3576, 0.1805)) / 0.95047;
    float y = dot(c, float3(0.2126, 0.7152, 0.0722));
    float z = dot(c, float3(0.0193, 0.1192, 0.9505)) / 1.08883;
    float fx = labF(x);
    float fy = labF(y);
    float fz = labF(z);
    return float3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz));
}

[dispatch(8, 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void computeLab(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= GR || id.y >= GR)
        return;

    float2 uv = (float2(id.xy) + 0.5) / float(GR);
    float o = 0.25 / float(GR);

    float3 c = cameraTex.SampleLevel(sampler, uv + float2(-o, -o), 0)
             + cameraTex.SampleLevel(sampler, uv + float2(o, -o), 0)
             + cameraTex.SampleLevel(sampler, uv + float2(-o, o), 0)
             + cameraTex.SampleLevel(sampler, uv + float2(o, o), 0);

    labRW[int2(id.xy)] = float4(rgbToLab(c * 0.25), 0.0);
}

// separable 5x5 binomial blur, kernel 1/16 [1, 4, 6, 4, 1]
static const float K5[5] = { 1.0 / 16.0, 4.0 / 16.0, 6.0 / 16.0, 4.0 / 16.0, 1.0 / 16.0 };

[dispatch(8, 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void computeBlurH(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= GR || id.y >= GR)
        return;
    float3 acc = float3(0, 0, 0);
    for (int k = -2; k <= 2; k++)
    {
        int x = clamp(int(id.x) + k, 0, GR - 1);
        acc += labRW[int2(x, id.y)].rgb * K5[k + 2];
    }
    tmpRW[int2(id.xy)] = float4(acc, 0.0);
}

[dispatch(8, 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void computeBlurV(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= GR || id.y >= GR)
        return;
    float3 acc = float3(0, 0, 0);
    for (int k = -2; k <= 2; k++)
    {
        int y = clamp(int(id.y) + k, 0, GR - 1);
        acc += tmpRW[int2(id.x, y)].rgb * K5[k + 2];
    }
    blurRW[int2(id.xy)] = float4(acc, 0.0);
}

// --- integral image: row prefix sums, one thread per row ---
[dispatch(8, 1, 1)]
[numthreads(8, 1, 1)]
[shader("compute")]
void computeSatRows(uint3 id : SV_DispatchThreadID)
{
    int y = int(id.x);
    if (y >= GR)
        return;
    float3 acc = float3(0, 0, 0);
    for (int x = 0; x < GR; x++)
    {
        acc += labRW[int2(x, y)].rgb;
        satBuf[y * GR + x] = float4(acc, 0.0);
    }
}

// --- integral image: column prefix sums, one thread per column ---
[dispatch(8, 1, 1)]
[numthreads(8, 1, 1)]
[shader("compute")]
void computeSatCols(uint3 id : SV_DispatchThreadID)
{
    int x = int(id.x);
    if (x >= GR)
        return;
    float3 acc = float3(0, 0, 0);
    for (int y = 0; y < GR; y++)
    {
        acc += satBuf[y * GR + x].rgb;
        satBuf[y * GR + x] = float4(acc, 0.0);
    }
}

// --- multi-scale center-surround saliency (AC method), one thread per cell ---
// window half-sizes GR/2, GR/4, GR/8, clamped to image bounds
[dispatch(8, 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void computeSaliency(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= GR || id.y >= GR)
        return;
    int x = int(id.x);
    int y = int(id.y);
    float3 c = blurRW[int2(x, y)].rgb;

    float s = 0.0;
    for (int t = 0; t < 3; t++)
    {
        int hw = GR >> (t + 1); // 32, 16, 8
        int x0 = max(x - hw, 0);
        int y0 = max(y - hw, 0);
        int x1 = min(x + hw, GR - 1);
        int y1 = min(y + hw, GR - 1);
        float3 sum = satBuf[y1 * GR + x1].rgb;
        if (x0 > 0)
            sum -= satBuf[y1 * GR + x0 - 1].rgb;
        if (y0 > 0)
            sum -= satBuf[(y0 - 1) * GR + x1].rgb;
        if (x0 > 0 && y0 > 0)
            sum += satBuf[(y0 - 1) * GR + x0 - 1].rgb;
        float area = float((x1 - x0 + 1) * (y1 - y0 + 1));
        s += length(c - sum / area);
    }

    // blend with Lab chroma C* = sqrt(a^2 + b^2) (vividness, no surround
    // comparison). Chroma is scaled x3 to match the 3-scale contrast sum;
    // the adaptive threshold absorbs the remaining scale difference.
    float chroma = length(c.yz) * 3.0;
    s = lerp(s, chroma, colorBlend);

    // temporal EMA: suppresses single-frame threshold crossings (flicker)
    salBuf[y * GR + x] = (frame == 0) ? s : lerp(salBuf[y * GR + x], s, SAL_EMA);
}

// --- saliency mean: row reduction, then a tiny total pass ---
[dispatch(8, 1, 1)]
[numthreads(8, 1, 1)]
[shader("compute")]
void computeRowSum(uint3 id : SV_DispatchThreadID)
{
    int y = int(id.x);
    if (y >= GR)
        return;
    float acc = 0.0;
    for (int x = 0; x < GR; x++)
        acc += salBuf[y * GR + x];
    rowSum[y] = acc;
}

[dispatch(1, 1, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
void computeTotal(uint3 id : SV_DispatchThreadID)
{
    if (id.x != 0)
        return;
    float acc = 0.0;
    for (int y = 0; y < GR; y++)
        acc += rowSum[y];
    rowSum[GR] = acc;
}

// --- adaptive threshold (Achanta 2009 Eq. 9), one thread per cell ---
[dispatch(8, 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void computeMask(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= GR || id.y >= GR)
        return;
    float meanS = rowSum[GR] / float(NCELL);
    float Ta = meanS * lerp(3.0, 1.2, sensitivity);
    int i = int(id.y) * GR + int(id.x);
    cellState[i] = (salBuf[i] > Ta) ? 1 : 0;
}

// --- morphological opening (cross structuring element), ping-pong buffers ---
[dispatch(8, 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void computeErode(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= GR || id.y >= GR)
        return;
    int x = int(id.x);
    int y = int(id.y);
    int i = y * GR + x;
    int v = cellState[i];
    if (v == 1)
    {
        if (x == 0 || x == GR - 1 || y == 0 || y == GR - 1 ||
            cellState[i - 1] == 0 || cellState[i + 1] == 0 ||
            cellState[i - GR] == 0 || cellState[i + GR] == 0)
            v = 0;
    }
    stackBuf[i] = v;
}

[dispatch(8, 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void computeDilate(uint3 id : SV_DispatchThreadID)
{
    if (id.x >= GR || id.y >= GR)
        return;
    int x = int(id.x);
    int y = int(id.y);
    int i = y * GR + x;
    int v = stackBuf[i];
    if (v == 0)
    {
        if ((x > 0 && stackBuf[i - 1] == 1) || (x < GR - 1 && stackBuf[i + 1] == 1) ||
            (y > 0 && stackBuf[i - GR] == 1) || (y < GR - 1 && stackBuf[i + GR] == 1))
            v = 1;
    }
    cellState[i] = v;
}

bool sameHue(float2 ab1, float2 ab2)
{
    float c1 = length(ab1);
    float c2 = length(ab2);
    if (c1 < CHROMA_NEUTRAL || c2 < CHROMA_NEUTRAL)
        return true; // near-neutral cells carry no hue constraint
    return dot(ab1, ab2) > HUE_JOIN_COS * c1 * c2;
}

float boxIoU(float4 a, float4 b) // rects as min.xy, max.xy
{
    float2 mn = max(a.xy, b.xy);
    float2 mx = min(a.zw, b.zw);
    float2 d = max(mx - mn, float2(0, 0));
    float inter = d.x * d.y;
    float areaA = (a.z - a.x) * (a.w - a.y);
    float areaB = (b.z - b.x) * (b.w - b.y);
    return inter / max(areaA + areaB - inter, 1e-6);
}

float4 trackRect(Track t) // state [u,v,s,r] -> rect
{
    float w = sqrt(max(t.sizeVel.x * t.sizeVel.z, 1e-6));
    float h = t.sizeVel.x / max(w, 1e-4);
    return float4(t.posVel.xy - float2(w, h) * 0.5, t.posVel.xy + float2(w, h) * 0.5);
}

[dispatch(1, 1, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
void computeDetect(uint3 id : SV_DispatchThreadID)
{
    if (id.x != 0)
        return;

    float dt = max(deltaTime, 1e-3);

    // Saliency, thresholding, and morphology run in the parallel passes above;
    // this single-thread pass only does the inherently sequential parts:
    // connected components, tracking, and the MST.

    // --- connected-component labeling (BFS flood fill) ---
    float4 detRect[MAXDET];
    float detArea[MAXDET];
    int nd = 0;

    for (int s0 = 0; s0 < NCELL; s0++)
    {
        if (cellState[s0] != 1)
            continue;

        int sp = 0;
        stackBuf[sp] = s0;
        sp++;
        cellState[s0] = 2;

        int mnx = GR, mny = GR, mxx = 0, mxy = 0;
        int area = 0;

        while (sp > 0)
        {
            sp--;
            int c = stackBuf[sp];
            int cx = c % GR;
            int cy = c / GR;
            mnx = min(mnx, cx);
            mny = min(mny, cy);
            mxx = max(mxx, cx);
            mxy = max(mxy, cy);
            area++;

            for (int n = 0; n < 4; n++)
            {
                int nx = cx + ((n == 0) ? 1 : (n == 1) ? -1 : 0);
                int ny = cy + ((n == 2) ? 1 : (n == 3) ? -1 : 0);
                if (nx < 0 || nx >= GR || ny < 0 || ny >= GR)
                    continue;
                int ni = ny * GR + nx;
                if (cellState[ni] == 1 &&
                    sameHue(blurRW[int2(cx, cy)].gb, blurRW[int2(nx, ny)].gb))
                {
                    cellState[ni] = 2;
                    stackBuf[sp] = ni;
                    sp++;
                }
            }
        }

        if (area < minBoxSize)
            continue;

        // keep largest MAXDET, sorted descending by area
        float4 r = float4(float(mnx) / float(GR), float(mny) / float(GR),
                          float(mxx + 1) / float(GR), float(mxy + 1) / float(GR));
        float a = float(area);
        int pos = min(nd, MAXDET - 1);
        for (; pos > 0 && detArea[pos - 1] < a; pos--)
        {
            detRect[pos] = detRect[pos - 1];
            detArea[pos] = detArea[pos - 1];
        }
        detRect[pos] = r;
        detArea[pos] = a;
        nd = min(nd + 1, MAXDET);
    }

    // --- SORT-style tracking ---
    if (frame == 0)
    {
        for (int t0 = 0; t0 < NTRACK; t0++)
        {
            Track z;
            z.posVel = float4(0, 0, 0, 0);
            z.sizeVel = float4(0, 0, 1, 0);
            z.meta = float4(0, 0, 0, 0);
            tracks[t0] = z;
        }
    }

    // predict: constant-velocity motion model
    for (int tp = 0; tp < NTRACK; tp++)
    {
        Track tr = tracks[tp];
        if (tr.meta.w < 0.5)
            continue;
        tr.posVel.xy += tr.posVel.zw * dt;
        tr.sizeVel.x = max(tr.sizeVel.x + tr.sizeVel.y * dt, 1e-5);
        tracks[tp] = tr;
    }

    // greedy IoU association (highest IoU first)
    bool detClaimed[MAXDET];
    for (int dc = 0; dc < MAXDET; dc++)
        detClaimed[dc] = false;
    bool trkMatched[NTRACK];
    for (int tm = 0; tm < NTRACK; tm++)
        trkMatched[tm] = false;

    for (int it = 0; it < NTRACK; it++)
    {
        float bestIoU = IOU_MIN;
        int bestT = -1;
        int bestD = -1;
        for (int t = 0; t < NTRACK; t++)
        {
            Track tr = tracks[t];
            if (tr.meta.w < 0.5 || trkMatched[t])
                continue;
            float4 pr = trackRect(tr);
            for (int j = 0; j < nd; j++)
            {
                if (detClaimed[j])
                    continue;
                float iou = boxIoU(pr, detRect[j]);
                if (iou > bestIoU)
                {
                    bestIoU = iou;
                    bestT = t;
                    bestD = j;
                }
            }
        }
        if (bestT < 0)
            break;

        trkMatched[bestT] = true;
        detClaimed[bestD] = true;

        // fixed-gain (steady-state Kalman / alpha-beta) update
        Track tr = tracks[bestT];
        float4 dr = detRect[bestD];
        float2 zc = (dr.xy + dr.zw) * 0.5;
        float2 wh = dr.zw - dr.xy;
        float zs = wh.x * wh.y;
        float zr = wh.x / max(wh.y, 1e-4);

        float2 resP = zc - tr.posVel.xy;
        tr.posVel.xy += POS_GAIN * resP;
        tr.posVel.zw += VEL_GAIN * resP / dt;
        tr.posVel.zw = clamp(tr.posVel.zw, -2.0, 2.0);

        float resS = zs - tr.sizeVel.x;
        tr.sizeVel.x += POS_GAIN * resS;
        tr.sizeVel.y = clamp(tr.sizeVel.y + VEL_GAIN * resS / dt, -1.0, 1.0);
        tr.sizeVel.z = lerp(tr.sizeVel.z, zr, POS_GAIN);

        tr.meta.x = min(tr.meta.x + 1.0, 1000.0);
        tr.meta.y = 0.0;
        tracks[bestT] = tr;
    }

    // unmatched tracks: age, kill after MAX_AGE
    for (int tu = 0; tu < NTRACK; tu++)
    {
        Track tr = tracks[tu];
        if (tr.meta.w < 0.5)
            continue;
        if (!trkMatched[tu])
        {
            tr.meta.y += 1.0;
            tr.posVel.zw *= 0.9; // damp velocity while coasting
            if (tr.meta.y > float(MAX_AGE))
                tr.meta.w = 0.0;
        }
        if (tu >= boxCount)
            tr.meta.w = 0.0;
        tracks[tu] = tr;
    }

    // unmatched detections: spawn new tracks (largest first)
    for (int j2 = 0; j2 < nd; j2++)
    {
        if (detClaimed[j2])
            continue;
        for (int t2 = 0; t2 < NTRACK; t2++)
        {
            if (t2 >= boxCount)
                break;
            Track tr = tracks[t2];
            if (tr.meta.w > 0.5)
                continue;
            float4 dr = detRect[j2];
            float2 wh = dr.zw - dr.xy;
            tr.posVel = float4((dr.xy + dr.zw) * 0.5, 0.0, 0.0);
            tr.sizeVel = float4(wh.x * wh.y, 0.0, wh.x / max(wh.y, 1e-4), 0.0);
            tr.meta = float4(1.0, 0.0, 0.0, 1.0);
            tracks[t2] = tr;
            break;
        }
    }

    // display: binary on/off — shown once confirmed (hits >= MIN_HITS), gone instantly
    for (int tv = 0; tv < NTRACK; tv++)
    {
        Track tr = tracks[tv];
        bool visible = tr.meta.w > 0.5 && tr.meta.x >= float(MIN_HITS) && tr.meta.y <= 1.0;
        tr.meta.z = visible ? 1.0 : 0.0;
        tracks[tv] = tr;
    }

    // --- minimum spanning tree over visible window centers (Prim) ---
    for (int lc = 0; lc < NTRACK; lc++)
        links[lc] = float4(0, 0, 0, 0);

    float2 nodes[NTRACK];
    float4 rects[NTRACK];
    int nn = 0;
    for (int g = 0; g < NTRACK; g++)
    {
        Track tr = tracks[g];
        if (tr.meta.z > 0.5)
        {
            nodes[nn] = tr.posVel.xy;
            rects[nn] = trackRect(tr);
            hudBoxes[1 + nn] = rects[nn];
            hudIds[nn] = g;
            nn++;
        }
    }
    int ne = 0;
    if (nn >= 2)
    {
        bool inTree[NTRACK];
        for (int q = 0; q < NTRACK; q++)
            inTree[q] = false;
        inTree[0] = true;
        for (int e = 0; e < nn - 1; e++)
        {
            float best = 1e9;
            int bi = -1;
            int bj = -1;
            for (int a = 0; a < nn; a++)
            {
                if (!inTree[a])
                    continue;
                for (int b2 = 0; b2 < nn; b2++)
                {
                    if (inTree[b2])
                        continue;
                    float2 dv = nodes[a] - nodes[b2];
                    float d2 = dot(dv, dv);
                    if (d2 < best)
                    {
                        best = d2;
                        bi = a;
                        bj = b2;
                    }
                }
            }
            if (bj < 0)
                break;
            inTree[bj] = true;

            // attach the edge to the closest pair of window corners
            float2 bestA = nodes[bi];
            float2 bestB = nodes[bj];
            float bestC = 1e9;
            for (int ca = 0; ca < 4; ca++)
            {
                float4 ra = rects[bi];
                float2 pa = float2((ca & 1) == 0 ? ra.x : ra.z, (ca & 2) == 0 ? ra.y : ra.w);
                for (int cb = 0; cb < 4; cb++)
                {
                    float4 rb = rects[bj];
                    float2 pb = float2((cb & 1) == 0 ? rb.x : rb.z, (cb & 2) == 0 ? rb.y : rb.w);
                    float2 dc = pa - pb;
                    float c2 = dot(dc, dc);
                    if (c2 < bestC)
                    {
                        bestC = c2;
                        bestA = pa;
                        bestB = pb;
                    }
                }
            }
            links[e] = float4(bestA, bestB);
            ne = e + 1;
        }
    }
    hudBoxes[0] = float4(float(nn), float(ne), 0.0, 0.0);
}

// --- 5x7 pixel font: 0-9, I, D, '/' — one 5-bit row per entry, 7 rows per glyph ---
static const int FONTROWS[91] = {
    14, 17, 19, 21, 25, 17, 14, // 0
    4, 12, 4, 4, 4, 4, 14,      // 1
    14, 17, 1, 2, 4, 8, 31,     // 2
    31, 2, 4, 2, 1, 17, 14,     // 3
    2, 6, 10, 18, 31, 2, 2,     // 4
    31, 16, 30, 1, 1, 17, 14,   // 5
    6, 8, 16, 30, 17, 17, 14,   // 6
    31, 1, 2, 4, 8, 8, 8,       // 7
    14, 17, 17, 14, 17, 17, 14, // 8
    14, 17, 17, 15, 1, 2, 12,   // 9
    14, 4, 4, 4, 4, 4, 14,      // I
    30, 17, 17, 17, 17, 17, 30, // D
    0, 0, 0, 0, 0, 12, 12       // .
};

bool glyphPix(int g, int2 p)
{
    if (g < 0 || g > 12 || p.x < 0 || p.x > 4 || p.y < 0 || p.y > 6)
        return false;
    return ((FONTROWS[g * 7 + p.y] >> (4 - p.x)) & 1) == 1;
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target
{
    float2 px = uv * resolution;
    float3 col = cameraTex.Sample(sampler, uv);

    float fs = max(2.0, round(resolution.y / 600.0));  // font pixel scale
    float lw = max(1.5, round(resolution.y / 840.0));  // box line half-width

    int nB = int(hudBoxes[0].x);
    int nL = int(hudBoxes[0].y);

    // MST links between window corners, drawn under the windows
    if (showLinks)
    {
        float lw2 = lw * 0.6;
        for (int li = 0; li < nL; li++)
        {
            float4 seg = links[li];
            float2 a = seg.xy * resolution;
            float2 b = seg.zw * resolution;
            // cheap AABB reject before the segment distance
            if (px.x < min(a.x, b.x) - lw2 || px.x > max(a.x, b.x) + lw2 ||
                px.y < min(a.y, b.y) - lw2 || px.y > max(a.y, b.y) + lw2)
                continue;
            float2 ab = b - a;
            float t = clamp(dot(px - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
            if (length(px - a - ab * t) < lw2)
                col = float3(1.0, 1.0, 1.0);
        }
    }

    float labelW = 31.0 * fs;
    float labelH = 9.0 * fs;

    for (int i = 0; i < nB; i++)
    {
        float4 r = hudBoxes[1 + i];
        float2 mn = r.xy * resolution;
        float2 mx = r.zw * resolution;

        // cheap reject against the union of box border and label tab
        if (px.x < mn.x - lw - 1.0 || px.x > max(mx.x, mn.x + labelW) + lw ||
            px.y < mn.y - labelH - 1.0 || px.y > mx.y + lw + 1.0)
            continue;

        float2 c = (mn + mx) * 0.5;
        float2 h = (mx - mn) * 0.5;
        float2 q = abs(px - c);

        bool vEdge = abs(q.x - h.x) < lw && q.y < h.y + lw;
        bool hEdge = abs(q.y - h.y) < lw && q.x < h.x + lw;

        if (vEdge || hEdge)
            col = float3(1.0, 1.0, 1.0);

        // label tab: white fill with "ID.nn" cut out, flush with the box top-left
        // 5 chars, 6-px advance, 1px padding: 2 + 5*6 - 1 = 31 x 9 font px.
        // The last text row must end at the border's top edge (mn.y - lw) so the
        // white border never overwrites the glyph cutouts; the bottom pad row
        // then overlaps the border white-on-white, keeping the tab seamless.
        float2 lo = float2(mn.x - lw, mn.y - 8.0 * fs - lw);
        float2 lp = (px - lo) / fs;
        if (lp.x >= 0.0 && lp.x < 31.0 && lp.y >= 0.0 && lp.y < 9.0)
        {
            int id = hudIds[i];
            int glyphs[5];
            glyphs[0] = 10; // I
            glyphs[1] = 11; // D
            glyphs[2] = 12; // .
            glyphs[3] = id / 10;
            glyphs[4] = id % 10;

            int tx = int(floor(lp.x)) - 1;
            int ty = int(floor(lp.y)) - 1;
            bool text = false;
            if (tx >= 0 && ty >= 0 && ty < 7)
            {
                int ci = tx / 6;
                int cx = tx % 6;
                text = ci < 5 && cx < 5 && glyphPix(glyphs[ci], int2(cx, ty));
            }
            if (!text)
                col = float3(1.0, 1.0, 1.0);
        }
    }

    return float4(col, 1.0);
}
