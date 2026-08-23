uniform float time;
uniform float deltaTime;
uniform float2 resolution;
uniform int frame;
uniform float3 touch;
uniform float microphone;
uniform Texture2D<float3> cameraTex;
uniform Texture2D<float4> backbuffer;
uniform SamplerState samp;

static const int W = 128;
static const int H = 128;
static const int NUM_LAYERS = 4;

struct State {
  float3 color;
  float x;
  float y;
  float z;
  float vx;
  float vy;
  float vz;
  float life;
  float maxLife;
}

[range(0.5, 10, 4)]
uniform float particleSize;

[range(0, 1, 0.1)]
uniform float scaleByLuminance;

[range(0, 1, 0.5)]
uniform float luminanceDepth;

[range(0, 5, 0.5)]
uniform float noiseStrength;

[range(0, 20, 2)]
uniform float drag;

[range(0.5, 5, 2)]
uniform float lifetime;

[range(0, 10, 4)]
uniform float touchForce;

[range(0, 30, 5)]
uniform float micEffect;

[range(-0.3, 0.3, 0.1)]
uniform float hueShift;


[range(0, 1, 1)]
uniform float trailFade;

[size(W * H)]
RWStructuredBuffer<State> buffer;

// hash-based noise
float hash(float2 p) {
  float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
  p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
  return frac((p3.x + p3.y) * p3.z);
}

float noise2d(float2 p) {
  float2 i = floor(p);
  float2 f = frac(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + float2(1, 0));
  float c = hash(i + float2(0, 1));
  float d = hash(i + float2(1, 1));
  return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

float fbm(float2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 2; i++) {
    v += a * noise2d(p);
    p *= 2.0;
    a *= 0.5;
  }
  return v;
}

// 2D curl noise with layer offset for pseudo-depth separation
float2 curlNoise2D(float2 p, int layer) {
  // each layer gets a unique offset so they flow differently
  float2 layerOffset = float2(float(layer) * 17.3, float(layer) * 31.7);
  float2 q = p + layerOffset;
  float eps = 0.01;
  float n0 = fbm(q);
  float nx = fbm(q + float2(eps, 0));
  float ny = fbm(q + float2(0, eps));
  float dnx = (nx - n0) / eps;
  float dny = (ny - n0) / eps;
  // curl: rotate gradient 90 degrees
  return float2(dny, -dnx);
}

float luminance(float3 c) {
  return dot(c, float3(0.299, 0.587, 0.114));
}

float3 rgb2hsv(float3 c) {
  float cmax = max(c.r, max(c.g, c.b));
  float cmin = min(c.r, min(c.g, c.b));
  float d = cmax - cmin;
  float h = 0;
  if (d > 0.0001) {
    if (cmax == c.r) h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
    else if (cmax == c.g) h = (c.b - c.r) / d + 2.0;
    else h = (c.r - c.g) / d + 4.0;
    h /= 6.0;
  }
  float s = cmax > 0.0001 ? d / cmax : 0.0;
  return float3(h, s, cmax);
}

float3 hsv2rgb(float3 c) {
  float h = c.x * 6.0;
  float s = c.y;
  float v = c.z;
  float i = floor(h);
  float f = h - i;
  float p = v * (1.0 - s);
  float q = v * (1.0 - s * f);
  float t = v * (1.0 - s * (1.0 - f));
  int ii = int(i) % 6;
  if (ii == 0) return float3(v, t, p);
  if (ii == 1) return float3(q, v, p);
  if (ii == 2) return float3(p, v, t);
  if (ii == 3) return float3(p, q, v);
  if (ii == 4) return float3(t, p, v);
  return float3(v, p, q);
}

float3 lerpHSV(float3 rgbA, float3 rgbB, float t) {
  float3 a = rgb2hsv(rgbA);
  float3 b = rgb2hsv(rgbB);
  // shortest path hue interpolation
  float dh = b.x - a.x;
  if (dh > 0.5) dh -= 1.0;
  if (dh < -0.5) dh += 1.0;
  float h = frac(a.x + dh * t);
  float s = lerp(a.y, b.y, t);
  float v = lerp(a.z, b.z, t);
  return hsv2rgb(float3(h, s, v));
}

[dispatch(16, 16, 1)]
[numthreads(8, 8, 1)]
void computeMain(uint3 id : SV_DispatchThreadID) {
  uint idx = id.y * W + id.x;
  let uv = float2(id.x / float(W), id.y / float(H));
  let color = cameraTex.SampleLevel(samp, uv, 0);
  var state = buffer[idx];
  state.color = color;

  float homeX = id.x / float(W);
  float homeY = 1.0 - id.y / float(H);
  float lum = luminance(color);
  int layer = clamp(int(lum * float(NUM_LAYERS)), 0, NUM_LAYERS - 1);
  float homeZ = (1.0 - float(layer) / float(NUM_LAYERS - 1)) * luminanceDepth;

  // randomized lifetime per particle (0.5x ~ 1.5x of base lifetime)
  float lifeRand = 0.5 + hash(float2(float(idx), time));

  if (frame == 0 || state.life <= 0) {
    state.x = homeX;
    state.y = homeY;
    state.z = homeZ;
    // smooth initial velocity from 2D curl noise
    float2 initCurl = curlNoise2D(float2(homeX * 3.0 + time * 0.2, homeY * 3.0 + time * 0.1), layer);
    state.vx = initCurl.x * 0.15;
    state.vy = initCurl.y * 0.15;
    state.vz = 0;
    // stagger initial spawn so they don't all reset at once
    if (frame == 0) {
      state.life = lifetime * lifeRand * hash(float2(float(idx), 1.0));
    } else {
      state.life = lifetime * lifeRand;
    }
    state.maxLife = state.life;
  } else {
    float dt = deltaTime;
    state.life -= dt;

    // 2D curl noise per layer
    float2 np = float2(state.x * 4.0 + time * 0.3, state.y * 4.0);
    float2 curl = curlNoise2D(np, layer);
    float micBoost = 1.0 + microphone * micEffect;
    float ax = curl.x * noiseStrength * micBoost;
    float ay = curl.y * noiseStrength * micBoost;

    // touch repulsion
    if (touch.z > 0.5) {
      float2 diff = float2(state.x - touch.x, state.y - (1.0 - touch.y));
      float dist = max(length(diff), 0.01);
      float2 dir = diff / dist;
      float falloff = 1.0 / (1.0 + dist * dist * 100.0);
      ax += dir.x * touchForce * falloff;
      ay += dir.y * touchForce * falloff;
    }

    // damping as drag force
    ax -= state.vx * drag;
    ay -= state.vy * drag;

    // semi-implicit Euler integration
    state.vx += ax * dt;
    state.vy += ay * dt;
    state.x += state.vx * dt;
    state.y += state.vy * dt;
    // z stays at layer depth (no z movement)
    state.z = homeZ;
  }
  buffer[idx] = state;
}

static const var QuadPositions = Array<float2, 4>(
    float2(-1.0, 1.0),
    float2(1.0, 1.0),
    float2(-1.0, -1.0),
    float2(1.0, -1.0));

struct VertexOut {
  float4 position : SV_Position;
  float3 color : COLOR;
  float alpha : ALPHA;
  float2 uv : TEXCOORD;
  float isBackground : BGFLAG;
};

float2 rot(float2 p, float a) {
  float c = cos(a);
  float s = sin(a);
  return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

[primitive(4, W * H)]
[shader("vertex")]
VertexOut vertexMain(uint id : SV_VertexID, uint iid : SV_InstanceID) {
  VertexOut v;

  v.isBackground = 0;
  v.uv = float2(0, 0);

  // iid==0: fullscreen background from backbuffer
  if (iid == 0) {
    v.position = float4(QuadPositions[id], 0.999, 1);
    v.uv = QuadPositions[id] * 0.5 + 0.5;
    v.uv.y = 1.0 - v.uv.y;
    v.color = float3(0, 0, 0);
    v.alpha = 1;
    v.isBackground = 1;
    return v;
  }

  let state = buffer[iid];
  let color = state.color;
  float lifeRatio = saturate(state.life / max(state.maxLife, 0.001));

  // cull nearly-dead particles to avoid black dot artifacts
  if (lifeRatio < 0.05) {
    v.position = float4(0, 0, 2, 1); // off-screen
    v.color = float3(0, 0, 0);
    v.alpha = 0;
    v.uv = float2(0, 0);
    v.isBackground = 0;
    return v;
  }
  // perspective scale: closer (bright) = bigger, farther (dark) = smaller
  float perspective = 1.0 / (1.0 + state.z * 2.0 + 0.01);
  var posOS = QuadPositions[id] * particleSize / float(W);
  var l = saturate(luminance(color));
  posOS *= 1.0 - scaleByLuminance + scaleByLuminance * l;
  // shrink as life fades, scale by depth
  posOS *= lifeRatio * perspective;
  // rotate toward velocity direction, suppress when slow
  float speed = length(float2(state.vx, state.vy));
  float angle = speed > 0.001 ? atan2(state.vy, state.vx) : 0.0;
  posOS = rot(posOS, angle);
  var pos = posOS + float2(state.x, state.y) * 2.0 - 1.0;
  v.position = float4(pos.x, pos.y, state.z, 1);
  // subtle hue shift as life fades
  float3 hsv = rgb2hsv(state.color);
  float t = 1.0 - lifeRatio;
  hsv.x = frac(hsv.x + t * hueShift);
  v.alpha = 1;
  v.color = hsv2rgb(hsv);
  return v;
}


[shader("fragment")]
float4 fragmentMain(VertexOut input) : SV_Target {
  if (input.isBackground > 0.5) {
    float3 prev = backbuffer.Sample(samp, input.uv).rgb;
    return float4(prev * trailFade, 1);
  }
  return float4(input.color, input.alpha);
}
