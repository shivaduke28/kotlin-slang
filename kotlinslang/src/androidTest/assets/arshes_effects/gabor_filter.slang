// Gabor Filter - directional texture extraction
// Compute shader at half resolution + bilinear sampling for performance
// Single mode: glowing directional edges
// Color mode: 4-direction orientation mapped to colors

uniform float time;
uniform float deltaTime;
uniform int frame;
uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;
uniform float3 touch;

[range(0.0, 180.0, 0.0)]
uniform float angle;

[range(2.0, 16.0, 5.0)]
uniform float wavelength;

[range(1.0, 4.0, 2.0)]
uniform float sigma;

[range(0.5, 5.0, 2.0)]
uniform float intensity;

[toggle(false)]
uniform bool colorMode;

static const float PI = 3.14159265;

// Half-resolution buffer: RGBA = 4 direction responses (color mode)
// or R = single direction response
[size2d(RESOLUTION_X / 2, RESOLUTION_Y / 2)]
RWTexture2D<float4> gaborRW;
Texture2D<float4> gabor;

float gaborKernel(float2 uv, float theta, float lambda, float sig) {
    int kSize = int(sig * 2.5);
    float sum = 0.0;
    float gamma = 0.5;
    float cosT = cos(theta);
    float sinT = sin(theta);

    // Step by 2 and offset by 0.5 to leverage bilinear filtering
    for (int dx = -kSize; dx <= kSize; dx += 2) {
        for (int dy = -kSize; dy <= kSize; dy += 2) {
            float fx = float(dx);
            float fy = float(dy);
            // Bilinear sampling: offset by 0.5 to average 2x2 neighborhood
            float2 sUV = uv + (float2(fx, fy) + 0.5) / resolution;

            float xp = fx * cosT + fy * sinT;
            float yp = -fx * sinT + fy * cosT;

            float gauss = exp(-(xp * xp + gamma * gamma * yp * yp) / (2.0 * sig * sig));
            float wave = cos(2.0 * PI * xp / lambda);

            float lum = dot(cameraTex.SampleLevel(samp, sUV, 0), float3(0.299, 0.587, 0.114));
            sum += lum * gauss * wave;
        }
    }
    return sum;
}

// Compute Gabor responses at half resolution
[dispatch(RESOLUTION_X / 16, RESOLUTION_Y / 16, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void computeGabor(uint3 id : SV_DispatchThreadID) {
    int2 halfRes = int2(RESOLUTION_X / 2, RESOLUTION_Y / 2);
    if (int(id.x) >= halfRes.x || int(id.y) >= halfRes.y) return;

    // Map half-res pixel to full-res UV
    float2 uv = (float2(id.xy) * 2.0 + 1.0) / resolution;

    if (colorMode) {
        // 4 directions: 0, 45, 90, 135 degrees
        float r0 = abs(gaborKernel(uv, 0.0, wavelength, sigma));
        float r1 = abs(gaborKernel(uv, PI * 0.25, wavelength, sigma));
        float r2 = abs(gaborKernel(uv, PI * 0.5, wavelength, sigma));
        float r3 = abs(gaborKernel(uv, PI * 0.75, wavelength, sigma));
        gaborRW[id.xy] = float4(r0, r1, r2, r3);
    } else {
        float theta = angle * PI / 180.0;
        float r = abs(gaborKernel(uv, theta, wavelength, sigma));
        gaborRW[id.xy] = float4(r, 0.0, 0.0, 1.0);
    }
}

float3 hsv2rgb(float h, float s, float v) {
    float c = v * s;
    float hp = h / 60.0;
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

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float3 cam = cameraTex.SampleLevel(samp, uv, 0);
    float lum = dot(cam, float3(0.299, 0.587, 0.114));

    // Bilinear sample from half-res Gabor texture
    float4 g = gabor.SampleLevel(samp, uv, 0);

    if (colorMode) {
        // Find dominant direction from 4 channels
        float4 dirs = g * intensity;
        float maxVal = max(max(dirs.x, dirs.y), max(dirs.z, dirs.w));
        float hue = 0.0;
        if (maxVal == dirs.x) hue = 0.0;     // 0°  -> red
        else if (maxVal == dirs.y) hue = 90.0;  // 45° -> green
        else if (maxVal == dirs.z) hue = 180.0; // 90° -> cyan
        else hue = 270.0;                       // 135°-> purple

        float brightness = saturate(maxVal);
        float3 color = hsv2rgb(hue, 1.0, 1.0);
        return float4(lum * 0.12 + color * brightness, 1.0);
    } else {
        float mag = g.r * intensity;
        float3 glow = float3(0.2, 0.8, 1.0) * mag;
        return float4(lum * 0.1 + glow, 1.0);
    }
}
