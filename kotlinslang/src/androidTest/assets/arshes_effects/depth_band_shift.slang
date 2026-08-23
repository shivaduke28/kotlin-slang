// Depth band shift
// Band-collapse effect modulated by depth: pixels inside/behind the band
// are pulled back along the band axis, but only in proportion to how far
// away they are. Near subjects stay intact; the background slides.

uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform Texture2D<float> depthTex;
uniform SamplerState samp;

[range(-1, 1, 0)]
uniform float rotation;

[range(0.0, 1.0, 0.25)]
uniform float width;

[range(0.0, 1.0, 0.5)]
uniform float centerX;

[range(0.0, 1.0, 0.5)]
uniform float centerY;

// depth (meters) where the shift starts to kick in
[range(0.0, 5.0, 0.5)]
uniform float depthNear;

// depth (meters) where the shift is fully applied
[range(0.0, 10.0, 2.0)]
uniform float depthFar;

#define PI 3.14159265359

float2 rotate(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    // work in aspect-corrected space so the band stays straight under rotation
    float2 asp = float2(resolution.x / resolution.y, 1.0);
    // +PI/2 so the band points up (screen -y) at rotation = 0
    float angle = -rotation * PI + 0.5 * PI;
    // band axis; signed distance from center along it is dot(p, v)
    float2 v = rotate(float2(1, 0), -angle);
    float s = dot((uv - float2(centerX, centerY)) * asp, v);

    // far pixels get the full band shift, near subjects are left in place
    float depth = max(0.0, depthTex.Sample(samp, uv));
    float f = smoothstep(depthNear, depthFar, depth);

    uv -= clamp(s, 0.0, width) * v / asp * f;
    float3 rgb = cameraTex.Sample(samp, fract(uv));
    return float4(rgb, 1);
}
