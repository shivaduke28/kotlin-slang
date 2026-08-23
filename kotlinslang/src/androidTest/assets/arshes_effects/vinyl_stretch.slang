uniform float2 resolution;
uniform float time;
uniform float3 touch;
uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;

// fraction of rings that get the effect
[range(0.0, 1.0, 1.0)]
uniform float density;

// random ring thickness range (fraction of image height; 0.001 = ~4px at 4K)
[range(0.001, 0.3, 0.02)]
uniform float ringMin;

[range(0.02, 0.5, 0.2)]
uniform float ringMax;

// how far along the circle the smear reaches (1 = full turn)
[range(0.0, 1.0, 0.5)]
uniform float stretch;

// shared angular offset for all bands (1 = full turn)
[range(-1.0, 1.0, 0.0)]
uniform float offset;

// per-ring start angle randomness: 0 = all bands aligned, 1 = fully random
[range(0.0, 1.0, 1.0)]
uniform float randomness;

// randomize smear direction (cw / ccw) per ring
[toggle(false)]
uniform bool randomDirection;

[range(0.0, 1.0, 0.5)]
uniform float centerX;

[range(0.0, 1.0, 0.5)]
uniform float centerY;

#define PI 3.14159265359
#define MAX_RINGS 64

// state[0].x = current seed, state[0].y = touch.z of previous frame
[size(1)]
RWStructuredBuffer<float4> state;

struct Ring {
    float edge;       // start radius of this ring
    float active;     // 1 = smear, 0 = pass through
    float startAngle; // random band start angle (0-1)
    float flip;       // 1 = reversed smear direction
};

// rings[MAX_RINGS].edge = end radius of the last ring
[size(65)]
RWStructuredBuffer<Ring> rings;

float hash(float n, float sd) {
    return frac(sin(n * 127.1 + sd * 311.7) * 43758.5453);
}

[dispatch(1, 1, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
void computeMain(uint3 id : SV_DispatchThreadID) {
    float4 s = state[0];
    // reroll the seed on touch down (rising edge)
    if (touch.z > 0.5 && s.y < 0.5) {
        s.x = frac(sin(time * 12.9898 + 78.233) * 43758.5453) * 100.0;
    }
    s.y = touch.z;
    state[0] = s;
    float seed = s.x;

    // build the ring table once per frame so the fragment shader
    // doesn't have to re-accumulate widths per pixel
    float edge = 0.0;
    for (int i = 0; i < MAX_RINGS; i++) {
        float fi = float(i);
        // cubed hash: mostly thin rings with occasional thick ones
        float h = hash(fi, seed);
        float w = lerp(ringMin, ringMax, h * h * h);

        Ring rg;
        rg.edge = edge;
        // golden-ratio sequence: ~density fraction of rings hit, evenly spread
        rg.active = (frac(fi * 0.6180339887 + hash(7.3, seed)) <= density) ? 1.0 : 0.0;
        rg.startAngle = hash(fi + 42.1, seed);
        rg.flip = (randomDirection && hash(fi + 91.7, seed) < 0.5) ? 1.0 : 0.0;
        rings[i] = rg;

        edge += w;
    }
    Ring last;
    last.edge = edge;
    last.active = 0.0;
    last.startAngle = 0.0;
    last.flip = 0.0;
    rings[MAX_RINGS] = last;
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    // aspect-corrected space so rings stay circular
    float2 asp = float2(resolution.x / resolution.y, 1.0);
    float2 p = (uv - float2(centerX, centerY)) * asp;
    float r = length(p);

    // outside the last ring: pass through
    if (r >= rings[MAX_RINGS].edge) {
        return float4(cameraTex.Sample(samp, uv), 1);
    }

    // binary search for the ring containing r
    int lo = 0;
    int hi = MAX_RINGS - 1;
    while (lo < hi) {
        int mid = (lo + hi + 1) / 2;
        if (r >= rings[mid].edge) {
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    Ring rg = rings[lo];

    if (rg.active < 0.5) {
        return float4(cameraTex.Sample(samp, uv), 1);
    }

    // per-ring random start angle (scaled by randomness) plus the shared offset
    float phase = (rg.startAngle * randomness + offset) * 2.0 * PI;

    // angular pixel stretch around the whole circle (single sector)
    float theta = atan2(p.y, p.x);
    float arc = 2.0 * PI;
    // pixels inside the smear region sample one edge of the band; outside stays put
    // flipped rings sample the far edge instead, reversing the smear direction
    float s = frac((theta + phase) / arc) * arc;
    float newTheta = (s <= stretch * arc) ? theta - s + rg.flip * stretch * arc : theta;

    float2 q = float2(centerX, centerY) + r * float2(cos(newTheta), sin(newTheta)) / asp;
    float3 rgb = cameraTex.Sample(samp, fract(q));
    return float4(rgb, 1);
}
