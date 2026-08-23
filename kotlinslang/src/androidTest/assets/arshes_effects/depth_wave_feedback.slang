// Depth wave feedback
// - Camera UV is wobbled by depth (closer objects wobble more)
// - Backbuffer is scrolled vertically and fed back onto bright, saturated areas

uniform float time;
uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform Texture2D<float4> backbuffer;
uniform Texture2D<float> depthTex;
uniform SamplerState samp;

[range(0, 1, 0.1)]
uniform float yShift;

[range(0, 1, 0.5)]
uniform float valueMin;

[range(0, 1, 0.1)]
uniform float valueOffset;

[range(0, 1, 0.5)]
uniform float satMin;

[range(0, 1, 0.1)]
uniform float satOffset;

[range(0, 1, 0.95)]
uniform float feedback;

float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 toGamma(float3 c) { return pow(max(float3(0.0), c), 1.0 / 2.2); }

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float depth = max(0, depthTex.Sample(samp, uv));

    // depth-driven wobble, stronger for closer objects
    float2 waveUv = uv + (sin((depth + time) * 3) + 1) / 100 * (0.01 + exp(-0.05 * depth));
    float3 cam = cameraTex.Sample(samp, waveUv);

    // feedback: scroll the backbuffer vertically
    float2 feedbackUv = waveUv + frac(time) * float2(0, yShift) * waveUv.y;
    float3 feedbackColor = backbuffer.Sample(samp, feedbackUv).rgb;

    // masks are computed in gamma space so the thresholds feel perceptually linear
    float3 feedbackHsv = rgb2hsv(toGamma(feedbackColor));
    float satMask = smoothstep(satMin, satMin + satOffset, feedbackHsv.g);
    feedbackColor *= satMask; // scaling linear RGB == scaling V

    // gamma-space V after the scale, without another conversion round-trip
    float feedbackValue = feedbackHsv.b * pow(satMask, 1.0 / 2.2);
    float valueMask = smoothstep(valueMin, valueMin + valueOffset, feedbackValue);

    float3 result = lerp(cam, feedbackColor, valueMask * feedback);
    return float4(result, 1);
}
