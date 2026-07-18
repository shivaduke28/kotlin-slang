// Blend mode test
// Pass 0: solid background (no blending)
// Pass 1: semi-transparent circle with alpha blending
// Expected: orange circle blended over blue background

struct VertexOutput {
    float4 position : SV_Position;
    float2 texCoord : TEXCOORD;
};

[pass(0)]
[shader("fragment")]
float4 background(VertexOutput input) : SV_Target {
    return float4(0.2, 0.3, 0.5, 1.0);
}

[pass(1)]
[blend(BlendMode.Alpha)]
[shader("fragment")]
float4 overlay(VertexOutput input) : SV_Target {
    float2 uv = input.texCoord;
    float d = length(uv - 0.5);
    float alpha = smoothstep(0.3, 0.2, d);
    return float4(1.0, 0.5, 0.0, alpha);
}
