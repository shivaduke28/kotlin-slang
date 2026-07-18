// Test: attributes
// rangeAttribute, rgbAttribute, toggleAttributeのパラメータ定義をテスト
// 期待: コンパイルが成功すればOK

[range(0.0, 1.0, 0.5)]
uniform float brightness;

[range(1, 10, 5)]
uniform int iterations;

[rgb(1.0, 0.5, 0.2)]
uniform float3 tintColor;

[toggle(true)]
uniform bool enabled;

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float3 col = tintColor * brightness;
    if (!enabled) {
        col = float3(0.0, 0.0, 0.0);
    }
    col *= float(iterations) / 10.0;
    return float4(col, 1.0);
}
