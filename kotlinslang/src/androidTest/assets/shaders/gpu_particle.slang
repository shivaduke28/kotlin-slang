// GPU Particle test
// Compute shader writes particle positions to RWStructuredBuffer,
// vertex shader reads them via SV_InstanceID (instanced quads).
// Expected: ring of colored quads

uniform float time;
uniform float2 resolution;

struct Particle {
    float4 position;
    float4 color;
};

static const int PARTICLE_COUNT = 64;

[size(64)]
RWStructuredBuffer<Particle> particles;

[dispatch(1, 1, 1)]
[numthreads(64, 1, 1)]
[shader("compute")]
void initParticles(uint3 id : SV_DispatchThreadID) {
    int i = int(id.x);
    if (i >= PARTICLE_COUNT) return;

    float fi = float(i) / float(PARTICLE_COUNT);
    float angle = fi * 6.2831853 + time * 0.5;
    float radius = 0.3 + 0.2 * sin(fi * 12.0 + time);

    float x = cos(angle) * radius;
    float y = sin(angle) * radius;

    particles[i].position = float4(x, y, 0.0, 1.0);

    // Color based on angle
    float3 col = float3(
        0.5 + 0.5 * sin(fi * 6.28 + 0.0),
        0.5 + 0.5 * sin(fi * 6.28 + 2.09),
        0.5 + 0.5 * sin(fi * 6.28 + 4.18)
    );
    particles[i].color = float4(col, 1.0);
}

struct VertexOutput {
    float4 position : SV_Position;
    float4 color : COLOR;
};

// 64 quads (4 vertices each, drawn as triangle strip instances)
[primitive(4, 64)]
[shader("vertex")]
VertexOutput vertexMain(uint vid : SV_VertexID, uint iid : SV_InstanceID) {
    VertexOutput o;

    Particle p = particles[iid];

    // Quad corners (triangle strip order)
    float aspect = resolution.x / resolution.y;
    float size = 0.03;
    float sx = size / aspect;
    float sy = size;

    float2 offsets[4] = {
        float2(-sx, -sy),
        float2(sx, -sy),
        float2(-sx, sy),
        float2(sx, sy)
    };

    o.position = p.position + float4(offsets[vid], 0.0, 0.0);
    o.color = p.color;
    return o;
}

[shader("fragment")]
float4 fragmentMain(VertexOutput input) : SV_Target {
    return input.color;
}
