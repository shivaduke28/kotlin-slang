// Temporal RGB Split - smooth per-channel lag
// Each RGB channel follows camera at different speeds
// Moving parts show chromatic aberration, static parts look normal

uniform float time;
uniform float2 resolution;
uniform int frame;
uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;

[range(0.01, 0.3, 0.05)]
uniform float lag;

// Stores lagged RGB: R=slowest, G=medium, B=fastest
[size2d(RESOLUTION_X, RESOLUTION_Y)]
RWTexture2D<float4> laggedRW;
Texture2D<float4> lagged;

[dispatch(RESOLUTION_X / 8, RESOLUTION_Y / 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void updateLagged(uint3 id : SV_DispatchThreadID) {
    int2 texSize = int2(resolution);
    if (int(id.x) >= texSize.x || int(id.y) >= texSize.y) return;

    float2 uv = (float2(id.xy) + 0.5) / resolution;
    float3 cam = cameraTex.SampleLevel(samp, uv, 0);
    float4 prev = laggedRW[id.xy];

    // Each channel blends at a different rate
    float rRate = lag;          // slowest (most lag)
    float gRate = lag * 3.0;    // medium
    float bRate = lag * 9.0;    // fastest (least lag)

    float r = lerp(prev.r, cam.r, min(rRate, 1.0));
    float g = lerp(prev.g, cam.g, min(gRate, 1.0));
    float b = lerp(prev.b, cam.b, min(bRate, 1.0));

    laggedRW[id.xy] = float4(r, g, b, 1.0);
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    return lagged.Sample(samp, uv);
}
