// Motion Trail - only moving things are visible, static fades to black
// Tap to freeze/unfreeze

uniform float time;
uniform float deltaTime;
uniform int frame;
uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform Texture2D<float4> backbuffer;
uniform SamplerState samp;
uniform float3 touch;

[range(0.01, 0.2, 0.05)]
uniform float motionThreshold;

[range(0.01, 0.5, 0.05)]
uniform float trailBlend;

[range(0.5, 3.0, 1.0)]
uniform float exposure;

[range(0.01, 0.5, 0.1)]
uniform float trailDecay;

[toggle(false)]
uniform bool showMotionMask;

struct State {
    int frozen;
    float prevTouchZ;
};

[size(1)]
RWStructuredBuffer<State> state;

// Ping-pong buffers to avoid compute-before-fragment race
[size2d(RESOLUTION_X, RESOLUTION_Y)]
RWTexture2D<float4> prevFrameARW;
Texture2D<float4> prevFrameA;

[size2d(RESOLUTION_X, RESOLUTION_Y)]
RWTexture2D<float4> prevFrameBRW;
Texture2D<float4> prevFrameB;

[dispatch(1, 1, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
void updateState(uint3 id : SV_DispatchThreadID) {
    State s = state[0];
    bool tap = touch.z > 0.5 && s.prevTouchZ < 0.5;
    s.prevTouchZ = touch.z;

    if (tap) {
        s.frozen = 1 - s.frozen;
    }

    state[0] = s;
}

// Write current camera to one buffer (ping-pong by frame parity)
[dispatch(RESOLUTION_X / 8, RESOLUTION_Y / 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void storePrevFrame(uint3 id : SV_DispatchThreadID) {
    if (state[0].frozen == 1) return;
    int2 texSize = int2(resolution);
    if (int(id.x) >= texSize.x || int(id.y) >= texSize.y) return;

    float2 uv = (float2(id.xy) + 0.5) / resolution;
    float3 cam = cameraTex.SampleLevel(samp, uv, 0);
    float4 pixel = float4(cam, 1.0);

    // Even frames write to A, odd frames write to B
    if (frame % 2 == 0) {
        prevFrameARW[id.xy] = pixel;
    } else {
        prevFrameBRW[id.xy] = pixel;
    }
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    if (state[0].frozen == 1) {
        return backbuffer.Sample(samp, uv);
    }

    float3 cam = cameraTex.Sample(samp, uv);

    // Read from the buffer NOT being written this frame
    float3 prev;
    if (frame % 2 == 0) {
        prev = prevFrameB.Sample(samp, uv).rgb; // B has last frame's camera
    } else {
        prev = prevFrameA.Sample(samp, uv).rgb; // A has last frame's camera
    }

    float4 prevResult = backbuffer.Sample(samp, uv);

    // Motion detection
    float3 diff = abs(cam - prev);
    float motion = dot(diff, float3(0.2126, 0.7152, 0.0722));
    bool isMotion = motion > motionThreshold;

    if (showMotionMask) {
        float m = smoothstep(motionThreshold * 0.5, motionThreshold * 1.5, motion);
        return float4(cam * (1.0 - m * 0.5) + float3(1.0, 0.0, 0.0) * m * 0.5, 1.0);
    }

    // Motion: draw with trail, Static: fade to black
    if (isMotion) {
        float3 trail = lerp(prevResult.rgb, cam * exposure, trailBlend);
        return float4(trail, 1.0);
    } else {
        float3 faded = prevResult.rgb * (1.0 - trailDecay);
        return float4(faded, 1.0);
    }
}
