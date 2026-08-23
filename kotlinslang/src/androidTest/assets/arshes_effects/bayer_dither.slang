uniform Texture2D<float3> cameraTex;
uniform SamplerState sampler;
uniform float2 resolution;

[range(0.0, 2.0, 1.0)]
uniform float contrast;

[range(-0.5, 0.5, 0.0)]
uniform float brightness;

[range(1.0, 16.0, 4.0)]
uniform float pixelSize;

[rgb(0.0, 0.0, 0.0)]
uniform float3 darkColor;

[rgb(1.0, 1.0, 1.0)]
uniform float3 lightColor;

static const float bayer8[64] = {
     0.0, 32.0,  8.0, 40.0,  2.0, 34.0, 10.0, 42.0,
    48.0, 16.0, 56.0, 24.0, 50.0, 18.0, 58.0, 26.0,
    12.0, 44.0,  4.0, 36.0, 14.0, 46.0,  6.0, 38.0,
    60.0, 28.0, 52.0, 20.0, 62.0, 30.0, 54.0, 22.0,
     3.0, 35.0, 11.0, 43.0,  1.0, 33.0,  9.0, 41.0,
    51.0, 19.0, 59.0, 27.0, 49.0, 17.0, 57.0, 25.0,
    15.0, 47.0,  7.0, 39.0, 13.0, 45.0,  5.0, 37.0,
    63.0, 31.0, 55.0, 23.0, 61.0, 29.0, 53.0, 21.0
};

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float2 pix = floor(uv * resolution / pixelSize);
    float2 quantUV = (pix * pixelSize + pixelSize * 0.5) / resolution;

    float3 rgb = cameraTex.SampleLevel(sampler, quantUV, 0);
    float lum = dot(rgb, float3(0.299, 0.587, 0.114));
    lum = saturate((lum - 0.5) * contrast + 0.5 + brightness);

    uint bx = uint(pix.x) & 7;
    uint by = uint(pix.y) & 7;
    float threshold = (bayer8[by * 8 + bx] + 0.5) / 64.0;

    float bw = lum > threshold ? 1.0 : 0.0;
    float3 color = lerp(darkColor, lightColor, bw);
    return float4(color, 1.0);
}
