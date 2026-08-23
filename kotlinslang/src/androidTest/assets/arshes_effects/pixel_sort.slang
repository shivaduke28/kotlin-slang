// Pixel sorting algorithm based on "20170723_pixelSorter" by FMS_Cat
// https://www.shadertoy.com/view/XsBfRG
// Licensed under CC BY-NC-SA 3.0
// https://creativecommons.org/licenses/by-nc-sa/3.0/

uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;
uniform float2 resolution;
uniform float time;
uniform float microphone;

static const int W = 1024;
static const int H = 1024;

[range(0.0, 1.0, 0.5)]
uniform float threshold;

[range(0.0, 20.0, 1.0)]
uniform float micEffect;

[toggle(false)]
uniform bool sortReverse;

[range(-3.0, 3.0, 0.0)]
uniform float exposure;

[range(-1.0, 1.0, 0.0)]
uniform float contrast;

[range(-1.0, 1.0, 0.0)]
uniform float saturation;

[range(-1.0, 1.0, 0.0)]
uniform float shadows;

[range(-1.0, 1.0, 0.0)]
uniform float highlights;

[range(0.0, 0.3, 0.0)]
uniform float grain;

[size(1)]
RWStructuredBuffer<float> micSmooth;

[size(1048576)]
RWStructuredBuffer<float4> sorted;

float gray(float3 c) {
    return dot(c, float3(0.299, 0.587, 0.114));
}

float3 toLinear(float3 c) { return pow(max(float3(0.0), c), 2.2); }
float3 toGamma(float3 c) { return pow(max(float3(0.0), c), 1.0 / 2.2); }

float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float3 colorGrade(float3 rgb) {
    rgb = toLinear(rgb);
    rgb *= pow(2.0, exposure);
    rgb = toGamma(rgb);
    float3 sm = 1.0 - rgb; sm = sm * sm;
    rgb = rgb + shadows * sm * 0.5;
    float3 hm = rgb * rgb;
    rgb = rgb + highlights * hm * 0.5;
    rgb = (rgb - 0.5) * (1.0 + contrast) + 0.5;
    float l = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    rgb = lerp(float3(l), rgb, 1.0 + saturation);
    return saturate(rgb);
}

// --- smoothMic ---
[dispatch(1, 1, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
void smoothMic(uint3 id : SV_DispatchThreadID) {
    micSmooth[0] = lerp(micSmooth[0], microphone, 0.2);
}

// --- readCamera ---
[dispatch(128, 128, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void readCamera(uint3 id : SV_DispatchThreadID) {
    int x = int(id.x);
    int y = int(id.y);
    if (x >= W || y >= H) return;
    float2 uv = (float2(id.xy) + 0.5) / float2(W, H);
    float3 col = colorGrade(cameraTex.Sample(samp, uv).rgb);
    sorted[y * W + x] = float4(col, gray(col));
}

// --- Phase 1: insertion sort within 32px blocks ---
// 1 thread per block, 32 blocks/row × 1024 rows = 32768 threads
[dispatch(32, 1024, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
void blockSort(uint3 id : SV_DispatchThreadID) {
    int blockIdx = int(id.x);
    int y = int(id.y);
    if (y >= H || blockIdx >= 32) return;

    int row = y * W;
    int start = blockIdx * 32;
    int end = start + 31;

    bool ascending = (blockIdx % 2) == 0;
    if (sortReverse) ascending = !ascending;

    for (int i = start + 1; i <= end; i++) {
        float4 key = sorted[row + i];
        int j = i - 1;
        while (j >= start) {
            bool sw = ascending ? (sorted[row + j].w > key.w) : (sorted[row + j].w < key.w);
            if (!sw) break;
            sorted[row + j + 1] = sorted[row + j];
            j--;
        }
        sorted[row + j + 1] = key;
    }
}

// --- Phase 2+: bitonic merge steps ---
void bitonicStep(uint3 id, int blockSize, int subBlockSize) {
    int x = int(id.x);
    int y = int(id.y);
    if (x >= W || y >= H) return;

    int half = subBlockSize / 2;
    int posInSub = x % subBlockSize;
    if (posInSub >= half) return;

    int row = y * W;
    int i = row + x;
    int j = i + half;

    bool ascending = ((x / blockSize) % 2) == 0;
    if (sortReverse) ascending = !ascending;

    float4 a = sorted[i];
    float4 b = sorted[j];
    bool sw = ascending ? (a.w > b.w) : (a.w < b.w);
    if (sw) {
        sorted[i] = b;
        sorted[j] = a;
    }
}

// Merge to 64
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m64a(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 64, 64); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m64b(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 64, 32); }

// Merge to 128
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m128a(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 128, 128); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m128b(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 128, 64); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m128c(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 128, 32); }

// Merge to 256
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m256a(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 256, 256); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m256b(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 256, 128); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m256c(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 256, 64); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m256d(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 256, 32); }

// Merge to 512
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m512a(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 512, 512); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m512b(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 512, 256); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m512c(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 512, 128); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m512d(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 512, 64); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m512e(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 512, 32); }

// Merge to 1024
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m1024a(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 1024, 1024); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m1024b(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 1024, 512); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m1024c(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 1024, 256); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m1024d(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 1024, 128); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m1024e(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 1024, 64); }
[dispatch(8, 1024, 1)]
[numthreads(128, 1, 1)]
[shader("compute")]
void m1024f(uint3 id : SV_DispatchThreadID) { bitonicStep(id, 1024, 32); }

// --- fragment ---
[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    int x = clamp(int(uv.x * float(W)), 0, W - 1);
    int y = clamp(int(uv.y * float(H)), 0, H - 1);
    float3 col = sorted[y * W + x].rgb;
    float noise = hash(uv * resolution + float2(time * 1000.0, 0.0)) * 2.0 - 1.0;
    col += noise * grain;
    return float4(saturate(col), 1.0);
}
