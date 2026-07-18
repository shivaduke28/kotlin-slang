// RWTexture2D view test
// RWTexture2D に compute で書き込み、Texture2D ビューで Sample して読む
// 期待: 赤→黒のグラデーション（バイリニア補間が効いている）

[size2d(RESOLUTION_X, RESOLUTION_Y)]
RWTexture2D<float4> canvasRW;

Texture2D<float4> canvas;

uniform SamplerState samp;
uniform float2 resolution;

[dispatch(RESOLUTION_X / 8, RESOLUTION_Y / 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void paint(uint3 id : SV_DispatchThreadID) {
    float2 uv = float2(id.xy) / resolution;
    canvasRW[id.xy] = float4(uv.x, 0.0, 0.0, 1.0);
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    return canvas.Sample(samp, uv);
}
