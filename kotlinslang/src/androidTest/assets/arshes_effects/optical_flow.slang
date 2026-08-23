// Optical Flow Particles
// Velocity field buffer smooths optical flow, particles ride it with inertia

uniform float time;
uniform float deltaTime;
uniform int frame;
uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;
uniform float3 touch;

[range(0.5, 5.0, 2.0)]
uniform float sensitivity;

[range(0.0, 2.0, 0.15)]
uniform float threshold;

[range(0.5, 8.0, 3.0)]
uniform float particleSize;

[range(0.1, 20.0, 1.8)]
uniform float flowForce;

[range(0.0, 0.2, 0.04)]
uniform float fieldDrag;

[range(0.0, 0.2, 0.02)]
uniform float particleDrag;

[range(0.5, 6.0, 2.5)]
uniform float lifetime;

static const float PI = 3.14159265;
static const int PARTICLE_COUNT = 10000;

// Previous frame luminance
[size2d(RESOLUTION_X, RESOLUTION_Y)]
RWTexture2D<float4> prevFrameRW;
Texture2D<float4> prevFrame;

// Raw optical flow (half res)
[size2d(RESOLUTION_X / 2, RESOLUTION_Y / 2)]
RWTexture2D<float4> flowRW;
Texture2D<float4> flow;

// Smoothed velocity field (half res): flow accumulates here as force
[size2d(RESOLUTION_X / 2, RESOLUTION_Y / 2)]
RWTexture2D<float4> velFieldRW;
Texture2D<float4> velField;

struct Particle {
    float2 pos;
    float2 vel;
    float life;
    float maxLife;
};

[size(10000)]
RWStructuredBuffer<Particle> particles;

float getLum(float2 uv) {
    return dot(cameraTex.SampleLevel(samp, uv, 0), float3(0.299, 0.587, 0.114));
}

float getPrevLum(float2 uv) {
    return prevFrame.SampleLevel(samp, uv, 0).r;
}

float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

float2 hash2(float n) {
    return float2(hash(n), hash(n + 127.1));
}

// --- Compute 1: Optical flow (half res, 3x3) ---
[dispatch(RESOLUTION_X / 16, RESOLUTION_Y / 16, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void computeFlow(uint3 id : SV_DispatchThreadID) {
    int2 halfRes = int2(RESOLUTION_X / 2, RESOLUTION_Y / 2);
    if (int(id.x) >= halfRes.x || int(id.y) >= halfRes.y) return;

    float2 uv = (float2(id.xy) * 2.0 + 1.0) / resolution;
    float2 texel = 1.0 / resolution;

    float sumIx2 = 0.0, sumIy2 = 0.0, sumIxIy = 0.0;
    float sumIxIt = 0.0, sumIyIt = 0.0;

    for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
            float2 p = uv + float2(float(dx), float(dy)) * texel * 2.0;
            float Ix = (getLum(p + float2(texel.x, 0.0)) - getLum(p - float2(texel.x, 0.0))) * 0.5;
            float Iy = (getLum(p + float2(0.0, texel.y)) - getLum(p - float2(0.0, texel.y))) * 0.5;
            float It = getLum(p) - getPrevLum(p);
            sumIx2 += Ix * Ix;
            sumIy2 += Iy * Iy;
            sumIxIy += Ix * Iy;
            sumIxIt += Ix * It;
            sumIyIt += Iy * It;
        }
    }

    float det = sumIx2 * sumIy2 - sumIxIy * sumIxIy;
    float2 flowVec = float2(0.0);
    if (abs(det) > 1e-6) {
        flowVec.x = (sumIy2 * (-sumIxIt) - sumIxIy * (-sumIyIt)) / det;
        flowVec.y = (sumIx2 * (-sumIyIt) - sumIxIy * (-sumIxIt)) / det;
    }
    flowVec = clamp(flowVec, -10.0, 10.0);
    float mag = length(flowVec);
    flowVec *= smoothstep(threshold * 0.5, threshold * 1.5, mag);

    flowRW[id.xy] = float4(flowVec, 0.0, 1.0);
}

// --- Compute 2: Update velocity field (flow as force + drag) ---
[dispatch(RESOLUTION_X / 16, RESOLUTION_Y / 16, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void updateVelField(uint3 id : SV_DispatchThreadID) {
    int2 halfRes = int2(RESOLUTION_X / 2, RESOLUTION_Y / 2);
    if (int(id.x) >= halfRes.x || int(id.y) >= halfRes.y) return;

    float2 f = flowRW[id.xy].xy;
    float2 vel = velFieldRW[id.xy].xy;

    // Optical flow as external force
    vel += f * flowForce;
    // Drag
    vel *= (1.0 - fieldDrag);

    velFieldRW[id.xy] = float4(vel, 0.0, 1.0);
}

// --- Compute 3: Store luminance ---
[dispatch(RESOLUTION_X / 8, RESOLUTION_Y / 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void storePrev(uint3 id : SV_DispatchThreadID) {
    if (int(id.x) >= RESOLUTION_X || int(id.y) >= RESOLUTION_Y) return;
    float2 uv = (float2(id.xy) + 0.5) / resolution;
    float lum = getLum(uv);
    prevFrameRW[id.xy] = float4(lum, 0.0, 0.0, 0.0);
}

// --- Compute 4: Update particles ---
[dispatch(10000 / 64, 1, 1)]
[numthreads(64, 1, 1)]
[shader("compute")]
void updateParticles(uint3 id : SV_DispatchThreadID) {
    if (int(id.x) >= PARTICLE_COUNT) return;

    Particle p = particles[id.x];

    // Respawn
    if (p.life <= 0.0 || p.pos.x < -0.05 || p.pos.x > 1.05 || p.pos.y < -0.05 || p.pos.y > 1.05) {
        float seed = float(id.x) * 7.31 + float(frame) * 0.037;
        p.pos = hash2(seed);
        p.vel = float2(0.0);
        p.maxLife = lifetime * (0.3 + hash(seed + 500.0) * 0.7);
        p.life = p.maxLife;
    }

    // Read smoothed velocity field as acceleration
    float2 fieldVel = velField.SampleLevel(samp, p.pos, 0).xy;
    p.vel += fieldVel * deltaTime;
    p.vel *= (1.0 - particleDrag);

    // Move
    p.pos += p.vel / resolution * deltaTime;
    p.life -= deltaTime;

    particles[id.x] = p;
}

// --- Pass 0: Black background ---
[pass(0)]
[shader("fragment")]
float4 background(float2 uv : TEXCOORD) : SV_Target {
    return float4(0.0, 0.0, 0.0, 1.0);
}

// --- Pass 1: Render particles ---
struct VertexOutput {
    float4 position : SV_Position;
    float4 color : COLOR;
    float2 quadUV : TEXCOORD0;
};

float3 hsv2rgb(float h, float s, float v) {
    float c = v * s;
    float hp = fmod(h / 60.0, 6.0);
    if (hp < 0.0) hp += 6.0;
    float x = c * (1.0 - abs(fmod(hp, 2.0) - 1.0));
    float3 rgb;
    if (hp < 1.0) rgb = float3(c, x, 0.0);
    else if (hp < 2.0) rgb = float3(x, c, 0.0);
    else if (hp < 3.0) rgb = float3(0.0, c, x);
    else if (hp < 4.0) rgb = float3(0.0, x, c);
    else if (hp < 5.0) rgb = float3(x, 0.0, c);
    else rgb = float3(c, 0.0, x);
    return rgb + (v - c);
}

[pass(1)]
[primitive(4, 10000)]
[shader("vertex")]
VertexOutput particleVert(uint vid : SV_VertexID, uint iid : SV_InstanceID) {
    Particle p = particles[iid];

    float2 corners[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 corner = corners[vid];

    float2 v = p.vel;
    float mag = length(v) * sensitivity;
    float2 pixelSize = particleSize / resolution;

    // Stretch backward along velocity
    if (mag > 0.03) {
        float2 velDir = normalize(v);
        float along = dot(corner, velDir);
        float perp = dot(corner, float2(-velDir.y, velDir.x));
        float stretchAmt = 1.0 + min(mag * 4.0, 12.0);
        float shifted = along * stretchAmt - min(mag, 3.0) * 2.0;
        corner = velDir * shifted + float2(-velDir.y, velDir.x) * perp * 0.3;
    }

    float2 pos = p.pos * 2.0 - 1.0;
    pos.y = -pos.y;

    VertexOutput o;
    o.position = float4(pos + corner * pixelSize, 0.0, 1.0);
    o.quadUV = corners[vid] * 0.5 + 0.5;

    float dir = atan2(v.y, v.x);
    float hue = fmod((dir / PI * 180.0) + 360.0, 360.0);
    float lifeRatio = saturate(p.life / max(p.maxLife, 0.001));
    float alpha = smoothstep(0.0, 0.1, lifeRatio) * smoothstep(0.0, 0.3, 1.0 - lifeRatio);
    alpha *= smoothstep(0.0, 0.3, mag);

    float brightness = 0.5 + saturate(mag * 2.0) * 0.5;
    o.color = float4(hsv2rgb(hue, 0.5 + saturate(mag) * 0.5, brightness), alpha);

    if (p.life <= 0.0) {
        o.position = float4(-10.0, -10.0, 0.0, 1.0);
    }

    return o;
}

[pass(1)]
[blend(BlendMode.Additive)]
[shader("fragment")]
float4 particleFrag(VertexOutput input) : SV_Target {
    float2 uv = input.quadUV * 2.0 - 1.0;
    float dist = dot(uv, uv);
    float glow = exp(-dist * 3.0);
    return float4(input.color.rgb * glow * input.color.a, glow * input.color.a);
}
