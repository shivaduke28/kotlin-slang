uniform float2 resolution;
uniform float3 touch;
uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;

// Sobel gradient magnitude, baked from the live camera at touch time.
[size2d(RESOLUTION_X, RESOLUTION_Y)]
RWTexture2D<float> gradRW;
// Read-only view of gradRW. Name must be gradRW with the "RW" suffix removed.
Texture2D<float> grad;

[range(0.0, 1.0, 0.15)]
uniform float edgeThreshold;

// Sobel sample spacing in pixels. Baked at capture time (touch to re-bake).
[range(1.0, 6.0, 2.0)]
uniform float lineWidth;

[rgb(1.0, 1.0, 1.0)]
uniform float3 lineColor;

float luma(float3 c) {
    return dot(c, float3(0.299, 0.587, 0.114));
}

// Bake the Sobel gradient directly from the live camera while touching.
// No intermediate snapshot buffer -> single compute pass, no cross-pass sync.
[dispatch((RESOLUTION_X + 7) / 8, (RESOLUTION_Y + 7) / 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void sobelCompute(uint3 id : SV_DispatchThreadID) {
    if (touch.z < 0.5) return;
    if (id.x >= uint(resolution.x) || id.y >= uint(resolution.y)) return;

    float2 uv = (float2(id.xy) + 0.5) / resolution;
    float2 texel = lineWidth / resolution;

    float l00 = luma(cameraTex.SampleLevel(samp, uv + texel * float2(-1.0, -1.0), 0));
    float l10 = luma(cameraTex.SampleLevel(samp, uv + texel * float2( 0.0, -1.0), 0));
    float l20 = luma(cameraTex.SampleLevel(samp, uv + texel * float2( 1.0, -1.0), 0));
    float l01 = luma(cameraTex.SampleLevel(samp, uv + texel * float2(-1.0,  0.0), 0));
    float l21 = luma(cameraTex.SampleLevel(samp, uv + texel * float2( 1.0,  0.0), 0));
    float l02 = luma(cameraTex.SampleLevel(samp, uv + texel * float2(-1.0,  1.0), 0));
    float l12 = luma(cameraTex.SampleLevel(samp, uv + texel * float2( 0.0,  1.0), 0));
    float l22 = luma(cameraTex.SampleLevel(samp, uv + texel * float2( 1.0,  1.0), 0));

    float gx = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
    float gy = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
    gradRW[id.xy] = length(float2(gx, gy));
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float3 cam = cameraTex.Sample(samp, uv);

    // Single tap into the baked gradient. threshold and color stay live.
    float g = grad.Sample(samp, uv);
    float m = step(edgeThreshold, g);
    float3 outc = lerp(cam, lineColor, m);
    return float4(outc, 1.0);
}
