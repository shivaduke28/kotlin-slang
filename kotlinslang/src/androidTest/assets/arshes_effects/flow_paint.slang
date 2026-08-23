// Flow Paint - tap to capture, motion permanently stretches the image
// Moving objects leave smeared trails in the captured photo

uniform float time;
uniform float deltaTime;
uniform int frame;
uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;
uniform float3 touch;

[range(0.0, 2.0, 0.1)]
uniform float threshold;

[range(0.1, 10.0, 1.0)]
uniform float smearStrength;

[range(5.0, 200.0, 50.0)]
uniform float maxDisplacement;

static const float PI = 3.14159265;

// Previous frame luminance
[size2d(RESOLUTION_X, RESOLUTION_Y)]
RWTexture2D<float4> prevFrameRW;
Texture2D<float4> prevFrame;

// Raw optical flow (half res)
[size2d(RESOLUTION_X / 2, RESOLUTION_Y / 2)]
RWTexture2D<float4> flowRW;
Texture2D<float4> flow;

// Accumulated displacement field (half res, RG = displacement)
[size2d(RESOLUTION_X / 2, RESOLUTION_Y / 2)]
RWTexture2D<float4> dispFieldRW;
Texture2D<float4> dispField;

// Captured camera image
[size2d(RESOLUTION_X, RESOLUTION_Y)]
RWTexture2D<float4> canvasRW;
Texture2D<float4> canvas;

struct State {
    float prevTouchZ;
    int captured;
    int justCaptured; // flag for capture frame
};

[size(1)]
RWStructuredBuffer<State> state;

float getLum(float2 uv) {
    return dot(cameraTex.SampleLevel(samp, uv, 0), float3(0.299, 0.587, 0.114));
}

float getPrevLum(float2 uv) {
    return prevFrame.SampleLevel(samp, uv, 0).r;
}

// --- Compute 1: Tap detection ---
[dispatch(1, 1, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
void detectTap(uint3 id : SV_DispatchThreadID) {
    State s = state[0];
    bool tap = touch.z > 0.5 && s.prevTouchZ < 0.5;
    s.prevTouchZ = touch.z;
    s.justCaptured = 0;

    if (tap) {
        if (s.captured == 0) {
            s.captured = 1;
            s.justCaptured = 1;
        } else {
            s.captured = 0;
        }
    }
    state[0] = s;
}

// --- Compute 2: Capture camera + clear displacement ---
[dispatch(RESOLUTION_X / 8, RESOLUTION_Y / 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void captureAndClear(uint3 id : SV_DispatchThreadID) {
    if (state[0].justCaptured == 0) return;

    // Capture camera to canvas
    if (int(id.x) < RESOLUTION_X && int(id.y) < RESOLUTION_Y) {
        float2 uv = (float2(id.xy) + 0.5) / resolution;
        float3 cam = cameraTex.SampleLevel(samp, uv, 0);
        canvasRW[id.xy] = float4(cam, 1.0);
    }

    // Clear displacement field
    int2 halfRes = int2(RESOLUTION_X / 2, RESOLUTION_Y / 2);
    int2 hid = int2(id.xy) / 2;
    if (hid.x < halfRes.x && hid.y < halfRes.y && (int(id.x) % 2 == 0) && (int(id.y) % 2 == 0)) {
        dispFieldRW[hid] = float4(0.0);
    }
}

// --- Compute 3: Optical flow ---
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

// --- Compute 4: Accumulate displacement ---
[dispatch(RESOLUTION_X / 16, RESOLUTION_Y / 16, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void accumDisp(uint3 id : SV_DispatchThreadID) {
    int2 halfRes = int2(RESOLUTION_X / 2, RESOLUTION_Y / 2);
    if (int(id.x) >= halfRes.x || int(id.y) >= halfRes.y) return;
    if (state[0].captured == 0) return;

    float2 f = flowRW[id.xy].xy;
    float2 disp = dispFieldRW[id.xy].xy;
    disp += f * smearStrength;

    // Clamp displacement magnitude
    float dispMag = length(disp);
    if (dispMag > maxDisplacement) {
        disp *= maxDisplacement / dispMag;
    }

    dispFieldRW[id.xy] = float4(disp, 0.0, 1.0);
}

// --- Compute 5: Store luminance ---
[dispatch(RESOLUTION_X / 8, RESOLUTION_Y / 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void storePrev(uint3 id : SV_DispatchThreadID) {
    if (int(id.x) >= RESOLUTION_X || int(id.y) >= RESOLUTION_Y) return;
    float2 uv = (float2(id.xy) + 0.5) / resolution;
    prevFrameRW[id.xy] = float4(getLum(uv), 0.0, 0.0, 0.0);
}

// --- Fragment ---
[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    if (state[0].captured == 1) {
        // Directional blur along displacement = stretching
        float2 disp = dispField.SampleLevel(samp, uv, 0).xy;
        float dispLen = length(disp);

        if (dispLen < 0.5) {
            return canvas.SampleLevel(samp, uv, 0);
        }

        // Sample along displacement direction
        int samples = clamp(int(dispLen * 0.5), 2, 16);
        float4 color = float4(0.0);
        for (int i = 0; i < samples; i++) {
            float t = float(i) / float(samples - 1);
            float2 offset = disp * t / resolution;
            float2 sampleUV = clamp(uv - offset, 0.0, 1.0);
            color += canvas.SampleLevel(samp, sampleUV, 0);
        }
        return color / float(samples);
    } else {
        // Live camera with blinking border
        float3 cam = cameraTex.SampleLevel(samp, uv, 0);
        float bw = 4.0;
        float2 px = uv * resolution;
        bool onBorder = px.x < bw || px.x > resolution.x - bw
                     || px.y < bw || px.y > resolution.y - bw;
        if (onBorder) {
            float blink = smoothstep(0.3, 0.7, sin(time * 4.0) * 0.5 + 0.5);
            return float4(lerp(cam, float3(1.0), blink), 1.0);
        }
        return float4(cam, 1.0);
    }
}
