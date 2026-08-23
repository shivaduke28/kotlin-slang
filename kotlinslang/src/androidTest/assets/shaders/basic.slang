// Test: basic
// Minimal shader: writes the UV straight out as colour.
// Expected: a gradient from black at the bottom left to yellow at the top right.

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    return float4(uv, 0.0, 1.0);
}
