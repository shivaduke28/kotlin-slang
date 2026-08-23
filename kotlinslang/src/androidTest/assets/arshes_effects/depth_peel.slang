// Depth Peel - quantize depth into layers and animate each with wave/parallax
// Fully real-time, no capture needed

uniform float time;
uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform Texture2D<float> depthTex;
uniform SamplerState samp;

[range(2, 20, 10)]
uniform int levels;

[range(0.5, 10.0, 3.0)]
uniform float maxDepth;

[range(0.0, 80.0, 30.0)]
uniform float waveAmount;

[range(0.1, 5.0, 1.5)]
uniform float waveSpeed;

[range(0.0, 150.0, 60.0)]
uniform float parallaxAmount;

[range(1.0, 20.0, 8.0)]
uniform float waveFreq;

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float depth = depthTex.Sample(samp, uv);
    float nd = saturate(depth / maxDepth);

    // Quantize depth
    int level = min(levels - 1, int(nd * float(levels)));
    float layerT = float(level) / float(levels - 1); // 0=near, 1=far

    // Parallax: near layers shift more
    float parallax = (1.0 - layerT) * parallaxAmount / resolution.x;
    float xShift = sin(time * waveSpeed * 0.7) * parallax;

    // Undulation wave
    float wave = sin(uv.y * waveFreq + time * waveSpeed + layerT * 5.0)
               * waveAmount * (1.0 - layerT * 0.5) / resolution.x;

    float2 offsetUV = uv + float2(xShift + wave, 0.0);
    float3 cam = cameraTex.Sample(samp, offsetUV);

    return float4(cam, 1.0);
}
