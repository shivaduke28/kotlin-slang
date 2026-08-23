uniform Texture2D<float3> cameraTex;
uniform SamplerState sampler;
uniform float3 touch;

struct DitherState {
    uint wasTouching;
    uint hasCaptured;
    uint captureRequested;
    uint iter;
};

[size(1)]
RWStructuredBuffer<DitherState> state;

[size2d(RESOLUTION_X / 4, RESOLUTION_Y / 4)]
RWTexture2D<float4> snapshotRW;

[size2d(RESOLUTION_X / 4, RESOLUTION_Y / 4)]
RWTexture2D<float4> errorARW;

[size2d(RESOLUTION_X / 4, RESOLUTION_Y / 4)]
RWTexture2D<float4> errorBRW;

[size2d(RESOLUTION_X / 4, RESOLUTION_Y / 4)]
RWTexture2D<float4> outputRW;

Texture2D<float4> output;

static const uint ITER_PER_FRAME = 8;

[dispatch(1, 1, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
void stateCompute(uint3 id : SV_DispatchThreadID) {
    uint wasTouching = state[0].wasTouching;
    bool touching = touch.z > 0.5;
    bool tapped = touching && (wasTouching == 0);
    state[0].wasTouching = touching ? 1u : 0u;

    if (tapped) {
        if (state[0].hasCaptured == 1) {
            state[0].hasCaptured = 0;
            state[0].captureRequested = 0;
            state[0].iter = 0;
        } else {
            state[0].captureRequested = 1;
            state[0].hasCaptured = 1;
            state[0].iter = 0;
        }
    } else if (state[0].captureRequested == 1) {
        state[0].captureRequested = 0;
        state[0].iter = ITER_PER_FRAME;
    } else if (state[0].hasCaptured == 1) {
        state[0].iter = state[0].iter + ITER_PER_FRAME;
    }
}

[dispatch(RESOLUTION_X / 32, RESOLUTION_Y / 32, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void blitCompute(uint3 id : SV_DispatchThreadID) {
    uint w, h;
    outputRW.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;

    if (state[0].captureRequested == 1) {
        float2 uv = (float2(id.xy) + 0.5) / float2(float(w), float(h));
        float3 rgb = cameraTex.SampleLevel(sampler, uv, 0);
        float lum = dot(rgb, float3(0.299, 0.587, 0.114));
        snapshotRW[id.xy] = float4(lum, 0.0, 0.0, 1.0);
        errorARW[id.xy] = float4(0.0, 0.0, 0.0, 0.0);
        errorBRW[id.xy] = float4(0.0, 0.0, 0.0, 0.0);
        outputRW[id.xy] = float4(lum, lum, lum, 1.0);
    } else if (state[0].hasCaptured == 0) {
        float2 uv = (float2(id.xy) + 0.5) / float2(float(w), float(h));
        float3 rgb = cameraTex.SampleLevel(sampler, uv, 0);
        float lum = dot(rgb, float3(0.299, 0.587, 0.114));
        outputRW[id.xy] = float4(lum, lum, lum, 1.0);
    }
}

void jacobiStep(uint3 id, bool readA, bool writeOutput) {
    uint w, h;
    snapshotRW.GetDimensions(w, h);
    if (id.x >= w || id.y >= h) return;
    if (state[0].captureRequested == 1) return;
    if (state[0].hasCaptured == 0) return;

    uint x = id.x;
    uint y = id.y;

    float e_left = 0.0, e_up = 0.0, e_upleft = 0.0, e_upright = 0.0;

    if (readA) {
        if (x > 0) e_left = errorARW[uint2(x - 1, y)].x;
        if (y > 0) e_up = errorARW[uint2(x, y - 1)].x;
        if (x > 0 && y > 0) e_upleft = errorARW[uint2(x - 1, y - 1)].x;
        if (x + 1 < w && y > 0) e_upright = errorARW[uint2(x + 1, y - 1)].x;
    } else {
        if (x > 0) e_left = errorBRW[uint2(x - 1, y)].x;
        if (y > 0) e_up = errorBRW[uint2(x, y - 1)].x;
        if (x > 0 && y > 0) e_upleft = errorBRW[uint2(x - 1, y - 1)].x;
        if (x + 1 < w && y > 0) e_upright = errorBRW[uint2(x + 1, y - 1)].x;
    }

    float incoming = e_left * (7.0 / 16.0)
                   + e_up * (5.0 / 16.0)
                   + e_upleft * (1.0 / 16.0)
                   + e_upright * (3.0 / 16.0);

    float baseLum = snapshotRW[uint2(x, y)].x;
    float target = baseLum + incoming;
    float outPix = target > 0.5 ? 1.0 : 0.0;
    float err = target - outPix;

    if (readA) {
        errorBRW[id.xy] = float4(err, 0.0, 0.0, 0.0);
    } else {
        errorARW[id.xy] = float4(err, 0.0, 0.0, 0.0);
    }

    if (writeOutput) {
        outputRW[id.xy] = float4(outPix, outPix, outPix, 1.0);
    }
}

[dispatch(RESOLUTION_X / 32, RESOLUTION_Y / 32, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void dither0(uint3 id : SV_DispatchThreadID) { jacobiStep(id, true, false); }

[dispatch(RESOLUTION_X / 32, RESOLUTION_Y / 32, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void dither1(uint3 id : SV_DispatchThreadID) { jacobiStep(id, false, false); }

[dispatch(RESOLUTION_X / 32, RESOLUTION_Y / 32, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void dither2(uint3 id : SV_DispatchThreadID) { jacobiStep(id, true, false); }

[dispatch(RESOLUTION_X / 32, RESOLUTION_Y / 32, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void dither3(uint3 id : SV_DispatchThreadID) { jacobiStep(id, false, false); }

[dispatch(RESOLUTION_X / 32, RESOLUTION_Y / 32, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void dither4(uint3 id : SV_DispatchThreadID) { jacobiStep(id, true, false); }

[dispatch(RESOLUTION_X / 32, RESOLUTION_Y / 32, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void dither5(uint3 id : SV_DispatchThreadID) { jacobiStep(id, false, false); }

[dispatch(RESOLUTION_X / 32, RESOLUTION_Y / 32, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void dither6(uint3 id : SV_DispatchThreadID) { jacobiStep(id, true, false); }

[dispatch(RESOLUTION_X / 32, RESOLUTION_Y / 32, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void dither7(uint3 id : SV_DispatchThreadID) { jacobiStep(id, false, true); }

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    uint w, h;
    output.GetDimensions(w, h);
    uint2 pix = uint2(uv * float2(float(w), float(h)));
    pix = clamp(pix, uint2(0, 0), uint2(w - 1, h - 1));
    float3 c = output[pix].rgb;
    return float4(c, 1.0);
}
