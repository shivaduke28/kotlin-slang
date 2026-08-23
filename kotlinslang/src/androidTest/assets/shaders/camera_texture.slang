// Covers resource reflection: binding index and space for a texture and a sampler, and
// the element type of Texture2D<float3>.

uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float3 col = cameraTex.Sample(samp, uv);
    return float4(col, 1.0);
}
