uniform Texture2D<float3> cameraTex;
uniform SamplerState ss;

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float3 cam = cameraTex.Sample(ss, uv);

    if (uv.x < 0.5) {
        // Left: raw cameraTex
        return float4(cam, 1.0);
    } else {
        // Right: assume sRGB input, convert to linear (pow 2.2)
        // If cameraTex is sRGB, this side will look darker but "correct" in linear
        // If cameraTex is already linear, this side will be way too dark
        return float4(pow(cam, 2.2), 1.0);
    }
}
