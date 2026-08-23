// Test: camera_texture
// Pass-through shader that displays the camera RGB texture unchanged.
// Expected: the camera image is shown as-is.

uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float3 col = cameraTex.Sample(samp, uv);
    return float4(col, 1.0);
}
