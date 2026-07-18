// Test: basic
// 最小構成のシェーダー。UVをそのまま色に出力する。
// 期待: 左下が黒、右上が黄色のグラデーション

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    return float4(uv, 0.0, 1.0);
}
