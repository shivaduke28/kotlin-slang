// Slit Scan - captures camera one column/row at a time
// Tap to start scanning, tap to pause/resume. Reaches the edge to auto-stop.
// Toggle vertical for top-to-bottom direction.

uniform float time;
uniform float deltaTime;
uniform int frame;
uniform float2 resolution;
uniform Texture2D<float3> cameraTex;
uniform SamplerState samp;
uniform float3 touch;

[toggle(true)]
uniform bool vertical;

[range(1, 10, 2)]
uniform int speed;

[range(0.0, 1.0, 0.1)]
uniform float scanStart;

[range(0.0, 1.0, 0.9)]
uniform float scanEnd;

struct State {
    float scanPos;
    int active;
    float prevTouchZ;
    int captureHead; // flag to capture before startPos
    int captureTail; // flag to capture after endPos
};

[size(1)]
RWStructuredBuffer<State> state;

[size2d(RESOLUTION_X, RESOLUTION_Y)]
RWTexture2D<float4> canvasRW;
Texture2D<float4> canvas;

// State management: tap detection, scan position advance
[dispatch(1, 1, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
void stateUpdate(uint3 id : SV_DispatchThreadID) {
    State s = state[0];
    bool tap = touch.z > 0.5 && s.prevTouchZ < 0.5;
    s.prevTouchZ = touch.z;

    float totalLen = vertical ? resolution.y : resolution.x;
    float startPos = scanStart * totalLen;
    float endPos = scanEnd * totalLen;

    if (tap) {
        if (s.active == 0) {
            if (s.scanPos >= endPos) {
                // Completed -> back to standby
                s.scanPos = 0.0;
                s.captureHead = 0;
                s.captureTail = 0;
            } else if (s.scanPos < startPos + 0.5) {
                // Standby -> start scanning, capture head
                s.scanPos = startPos;
                s.active = 1;
                s.captureHead = 1;
                s.captureTail = 0;
            } else {
                // Paused -> resume
                s.active = 1;
            }
        } else {
            // Pause
            s.active = 0;
        }
    }

    if (s.active == 1) {
        s.scanPos += float(speed);
        if (s.scanPos >= endPos) {
            s.scanPos = endPos;
            s.active = 0;
            s.captureTail = 1;
        }
    }

    state[0] = s;
}

// Copy camera pixels in current scan range to canvas
[dispatch(RESOLUTION_X / 8, RESOLUTION_Y / 8, 1)]
[numthreads(8, 8, 1)]
[shader("compute")]
void scanCopy(uint3 id : SV_DispatchThreadID) {
    // Skip entirely when idle
    if (state[0].active == 0 && state[0].captureHead == 0 && state[0].captureTail == 0) return;

    int2 texSize = int2(resolution);
    if (int(id.x) >= texSize.x || int(id.y) >= texSize.y) return;

    float totalLen = vertical ? resolution.y : resolution.x;
    float startPos = scanStart * totalLen;
    float endPos = scanEnd * totalLen;
    float coord = vertical ? float(id.y) : float(id.x);
    float2 uv = (float2(id.xy) + 0.5) / resolution;

    bool shouldCopy = false;

    // Capture head region (before startPos)
    if (state[0].captureHead == 1 && coord < startPos) {
        shouldCopy = true;
    }

    // Capture tail region (after endPos)
    if (state[0].captureTail == 1 && coord >= endPos) {
        shouldCopy = true;
    }

    // Copy last strip on completion (scanPos was advanced but active was cleared)
    if (state[0].captureTail == 1) {
        float scanPos = state[0].scanPos;
        float prevPos = max(startPos, scanPos - float(speed));
        if (coord >= prevPos && coord < scanPos) {
            shouldCopy = true;
        }
    }

    // Normal scan copy
    if (state[0].active == 1) {
        float scanPos = state[0].scanPos;
        float prevPos = max(startPos, scanPos - float(speed));
        if (coord >= prevPos && coord < scanPos) {
            shouldCopy = true;
        }
    }

    if (shouldCopy) {
        float3 cam = cameraTex.SampleLevel(samp, uv, 0);
        canvasRW[id.xy] = float4(cam, 1.0);
    }
}

// Clear one-shot capture flags after scanCopy has used them
[dispatch(1, 1, 1)]
[numthreads(1, 1, 1)]
[shader("compute")]
void clearFlags(uint3 id : SV_DispatchThreadID) {
    state[0].captureHead = 0;
    state[0].captureTail = 0;
}

[shader("fragment")]
float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
    float scanPos = state[0].scanPos;
    float totalLen = vertical ? resolution.y : resolution.x;
    float startPos = scanStart * totalLen;
    float endPos = scanEnd * totalLen;
    float coord = vertical ? uv.y * resolution.y : uv.x * resolution.x;
    float3 cam = cameraTex.SampleLevel(samp, uv, 0);

    // Standby: blinking white border
    bool standby = state[0].active == 0 && scanPos < startPos + 0.5;
    if (standby) {
        float bw = 3.0;
        float2 px = uv * resolution;
        bool onBorder = px.x < bw || px.x > resolution.x - bw
                     || px.y < bw || px.y > resolution.y - bw;
        float blink = smoothstep(0.3, 0.7, sin(time * 4.0) * 0.5 + 0.5);
        if (onBorder) {
            return float4(lerp(cam, float3(1.0), blink), 1.0);
        }
    }

    bool completed = state[0].active == 0 && scanPos >= endPos;

    // Start/end range lines (white) - hide when completed
    if (!completed) {
        if (abs(coord - startPos) < 1.5 || abs(coord - endPos) < 1.5) {
            return float4(1.0, 1.0, 1.0, 1.0);
        }
    }

    // Scan line indicator (red)
    if (state[0].active == 1 && abs(coord - scanPos) < 1.5) {
        return float4(1.0, 0.0, 0.0, 1.0);
    }

    // Captured area: show canvas
    if (scanPos > startPos) {
        // Scan region
        if (coord >= startPos && coord < scanPos) {
            return canvas.SampleLevel(samp, uv, 0);
        }
        // Head region (captured at start)
        if (coord < startPos) {
            return canvas.SampleLevel(samp, uv, 0);
        }
        // Tail region (captured at end)
        if (completed && coord >= endPos) {
            return canvas.SampleLevel(samp, uv, 0);
        }
    }

    // Live camera
    return float4(cam, 1.0);
}
