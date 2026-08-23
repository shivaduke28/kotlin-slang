uniform Texture2D<float3> cameraTex;
uniform SamplerState sampler;

[rgb(0.04, 0.18, 0.78)]
uniform float3 skyTarget;

[range(0.0, 0.5, 0.15)]
uniform float skyHueRange;

[range(0.0, 0.1, 0.02)]
uniform float skyHueFeather;

[range(0.0, 1.0, 0.9)]
uniform float skyHueShift;

[range(0.0, 2.0, 1.2)]
uniform float skySatBoost;

[range(0.0, 1.0, 0.8)]
uniform float outsideDesat;

float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float3 src = cameraTex.Sample(sampler, uv);
    float3 hsv = rgb2hsv(src);

    float targetH = rgb2hsv(skyTarget).x;

    // circular hue distance (0..0.5)
    float hd = abs(hsv.x - targetH);
    hd = min(hd, 1.0 - hd);

    // 1.0 inside range, 0.0 outside (with feather)
    float inner = max(skyHueRange - skyHueFeather, 0.0);
    float skyMask = 1.0 - smoothstep(inner, skyHueRange, hd);

    // shortest-path hue delta toward target
    float dh = targetH - hsv.x;
    dh -= step(0.5, dh);
    dh += step(dh, -0.5);

    float newH = frac(hsv.x + dh * skyHueShift * skyMask + 1.0);

    // sat: boost inside range, desaturate outside
    float satScale = lerp(1.0 - outsideDesat, skySatBoost, skyMask);
    float newS = saturate(hsv.y * satScale);

    // value untouched — leave luminance to the color-grade preprocess
    float3 outHsv = float3(newH, newS, hsv.z);
    float3 outRgb = hsv2rgb(outHsv);

    return float4(outRgb, 1.0);
}
