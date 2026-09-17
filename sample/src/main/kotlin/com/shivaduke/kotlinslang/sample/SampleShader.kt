package com.shivaduke.kotlinslang.sample

/** A tiny shader used by both the activity and the instrumentation test. */
object SampleShader {
    const val SOURCE = """
        struct VSOutput {
            float4 position : SV_Position;
        };

        [shader("vertex")]
        VSOutput vertexMain(uint vertexId : SV_VertexID) {
            VSOutput output;
            output.position = float4(0.0, 0.0, 0.0, 1.0);
            return output;
        }

        [shader("fragment")]
        float4 fragmentMain(VSOutput input) : SV_Target {
            return float4(1.0, 0.0, 1.0, 1.0);
        }
    """
}
