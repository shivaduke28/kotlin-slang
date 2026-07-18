// Test: camera_texture
// カメラRGBテクスチャをそのまま表示するパススルーシェーダー
// 期待: カメラ映像がそのまま表示される

uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float3 col = cameraTex.Sample(samp, uv);
    return float4(col, 1.0);
}
