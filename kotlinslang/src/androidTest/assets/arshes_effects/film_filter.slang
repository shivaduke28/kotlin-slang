uniform float time;
uniform int frame;
uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;

[range(0.5, 3.0, 1.0)]
uniform float aspectRatio;

[range(0.0, 0.1, 0.03)]
uniform float borderWidth;

[range(0.0, 1.0, 0.3)]
uniform float grainAmount;

[range(1.0, 8.0, 1.0)]
uniform float grainSize;

[toggle(false)]
uniform bool colorNoise;

float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float2 hashGrad(float2 p) {
    float a = hash(p) * 6.2831853;
    return float2(cos(a), sin(a));
}

float gradientNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float a = dot(hashGrad(i), f);
    float b = dot(hashGrad(i + float2(1.0, 0.0)), f - float2(1.0, 0.0));
    float c = dot(hashGrad(i + float2(0.0, 1.0)), f - float2(0.0, 1.0));
    float d = dot(hashGrad(i + float2(1.0, 1.0)), f - float2(1.0, 1.0));
    return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
}

static const int GRAIN_OCTAVES = 4;
static const float BASE_RES = 1080.0;

float filmGrain(float2 uv, float size, int f) {
    float2 seed = float2(hash(float2(float(f), 0.0)), hash(float2(0.0, float(f)))) * 10000.0;
    float2 p = (uv * BASE_RES + seed) / max(1.0, size);

    float n = gradientNoise(p);
    float totalAmp = 1.0;
    float amp = 0.5;
    float freq = 2.0;

    for (int i = 1; i <= GRAIN_OCTAVES; i++) {
        n += gradientNoise(p * freq) * amp;
        totalAmp += amp;
        freq *= 2.0;
        amp *= 0.5;
    }

    return n / totalAmp;
}

float3 softLight(float3 base, float3 blend) {
    float3 dark = 2.0 * base * blend + base * base * (1.0 - 2.0 * blend);
    float3 light = sqrt(base) * (2.0 * blend - 1.0) + 2.0 * base * (1.0 - blend);
    return lerp(dark, light, step(0.5, blend));
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float screenAspect = resolution.x / resolution.y;

    float2 cropSize;
    if (aspectRatio > screenAspect) {
        cropSize = float2(1.0, screenAspect / aspectRatio);
    } else {
        cropSize = float2(aspectRatio / screenAspect, 1.0);
    }

    float2 cropMin = (1.0 - cropSize) * 0.5;
    float2 cropMax = cropMin + cropSize;

    float bx = borderWidth;
    float by = borderWidth * screenAspect;
    float2 imgMin = cropMin + float2(bx, by);
    float2 imgMax = cropMax - float2(bx, by);

    if (uv.x < imgMin.x || uv.x > imgMax.x || uv.y < imgMin.y || uv.y > imgMax.y) {
        return float4(1.0, 1.0, 1.0, 1.0);
    }

    float3 col = cameraTex.Sample(samp, uv);

    float luma = dot(col, float3(0.2126, 0.7152, 0.0722));
    float response = luma * (1.0 - luma) * 4.0;

    float3 grainVal;
    if (colorNoise) {
        grainVal = float3(
            filmGrain(uv, grainSize, frame * 3),
            filmGrain(uv, grainSize, frame * 3 + 1),
            filmGrain(uv, grainSize, frame * 3 + 2)
        );
    } else {
        float n = filmGrain(uv, grainSize, frame);
        grainVal = float3(n);
    }

    float3 blend = 0.5 + grainVal * grainAmount * response;
    col = softLight(col, blend);

    return float4(col, 1.0);
}
