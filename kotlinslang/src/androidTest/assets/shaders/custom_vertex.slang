// Custom vertex shader test
// Draws a single triangle using instancing
// Expected: a colored triangle in the center of the screen

struct VertexOutput {
    float4 position : SV_Position;
    float3 color : COLOR;
};

[primitive(3, 1)]
[shader("vertex")]
VertexOutput vertexMain(uint vid : SV_VertexID, uint iid : SV_InstanceID) {
    VertexOutput o;

    // 3 vertices of a triangle
    float2 positions[3] = {
        float2(0.0, 0.5),
        float2(-0.5, -0.5),
        float2(0.5, -0.5)
    };
    float3 colors[3] = {
        float3(1.0, 0.0, 0.0),
        float3(0.0, 1.0, 0.0),
        float3(0.0, 0.0, 1.0)
    };

    o.position = float4(positions[vid], 0.0, 1.0);
    o.color = colors[vid];
    return o;
}

[shader("fragment")]
float4 fragmentMain(VertexOutput input) : SV_Target {
    return float4(input.color, 1.0);
}
