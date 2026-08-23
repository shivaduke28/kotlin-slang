uniform float time;
uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;

[range(-1.0, 1.0, 0.0)]
uniform float temperature;

[range(-3.0, 3.0, 0.0)]
uniform float exposure;

[range(-1.0, 1.0, 0.0)]
uniform float contrast;

[range(-1.0, 1.0, 0.0)]
uniform float saturation;

[range(-1.0, 1.0, 0.0)]
uniform float highlights;

[range(-1.0, 1.0, 0.0)]
uniform float shadows;

[range(-1.0, 1.0, 0.0)]
uniform float whites;

[range(-1.0, 1.0, 0.0)]
uniform float blacks;

[rgb(0.5, 0.5, 0.5)]
uniform float3 shadowTint;

[rgb(0.5, 0.5, 0.5)]
uniform float3 midtoneTint;

[rgb(0.5, 0.5, 0.5)]
uniform float3 highlightTint;

[range(0.0, 1.0, 0.5)]
uniform float tintStrength;

[range(0.0, 0.3, 0.0)]
uniform float grain;

float hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float3 toLinear(float3 c) { return pow(max(float3(0.0), c), 2.2); }
float3 toGamma(float3 c) { return pow(max(float3(0.0), c), 1.0 / 2.2); }

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float3 rgb = toLinear(cameraTex.Sample(samp, uv));

    // white balance (temperature)
    rgb.r *= 1.0 + temperature * 0.5;
    rgb.g *= 1.0 - abs(temperature) * 0.1;
    rgb.b *= 1.0 - temperature * 0.5;

    // exposure (EV stops)
    rgb *= pow(2.0, exposure);

    // convert to gamma space for tone adjustments
    rgb = toGamma(rgb);

    float3 lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));

    // blacks: lift the bottom end
    rgb = rgb + blacks * (1.0 - rgb) * (1.0 - rgb);

    // whites: push the top end
    rgb = rgb + whites * rgb * rgb;

    // shadows: affect dark regions
    float3 shadowMask = 1.0 - rgb;
    shadowMask = shadowMask * shadowMask;
    rgb = rgb + shadows * shadowMask * 0.5;

    // highlights: affect bright regions
    float3 highlightMask = rgb * rgb;
    rgb = rgb + highlights * highlightMask * 0.5;

    // contrast: S-curve around mid-gray
    rgb = rgb - 0.5;
    rgb = rgb * (1.0 + contrast);
    rgb = rgb + 0.5;

    // saturation
    lum = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    rgb = lerp(lum, rgb, 1.0 + saturation);

    // color grading (tint by tonal range)
    float lum2 = dot(rgb, float3(0.2126, 0.7152, 0.0722));
    float shadowMask2 = 1.0 - smoothstep(0.0, 0.5, lum2);
    float highlightMask2 = smoothstep(0.5, 1.0, lum2);
    float midtoneMask = 1.0 - shadowMask2 - highlightMask2;

    float3 shadowShift = (shadowTint - 0.5) * 2.0;
    float3 midtoneShift = (midtoneTint - 0.5) * 2.0;
    float3 highlightShift = (highlightTint - 0.5) * 2.0;

    float3 tint = shadowShift * shadowMask2 + midtoneShift * midtoneMask + highlightShift * highlightMask2;
    rgb += tint * tintStrength;

    // grain
    float noise = hash(uv * resolution + float2(time * 1000.0, 0.0)) * 2.0 - 1.0;
    rgb += noise * grain;

    rgb = saturate(rgb);

    return float4(rgb, 1.0);
}
