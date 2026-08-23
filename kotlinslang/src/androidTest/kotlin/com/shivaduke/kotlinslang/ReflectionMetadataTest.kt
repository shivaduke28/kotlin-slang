package com.shivaduke.kotlinslang

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/**
 * エントリポイントのユーザー属性と、暗黙のグローバル定数バッファのbinding/sizeが
 * リフレクションから取れることを検証する。シェーダーはこのファイル内で完結させる。
 */
@RunWith(AndroidJUnit4::class)
class ReflectionMetadataTest {

    private val compiler = SlangCompiler()

    private val attributeDecls = """
        [__AttributeUsage(_AttributeTargets.Function)]
        struct topologyAttribute { int mode; int count; };

        [__AttributeUsage(_AttributeTargets.Function)]
        struct scaleAttribute { float value; };
    """.trimIndent()

    /** uniformスカラ/ベクタとリソースを両方持つシェーダー。 */
    private val uniformsAndResources = """
        $attributeDecls

        uniform float amount;
        uniform float3 tint;
        Texture2D<float4> tex;
        SamplerState samp;

        [topology(4, 64)]
        [shader("vertex")]
        float4 vertexMain(uint vid : SV_VertexID) : SV_Position { return float4(0, 0, 0, 1); }

        [scale(1.5)]
        [shader("fragment")]
        float4 fragmentMain() : SV_Target {
            return tex.Sample(samp, float2(0, 0)) * amount + float4(tint, 1);
        }

        [shader("compute")]
        [numthreads(8, 8, 1)]
        void computeMain(uint3 id : SV_DispatchThreadID) { }
    """.trimIndent()

    /** uniformを1つも持たないシェーダー。 */
    private val resourcesOnly = """
        Texture2D<float4> tex;
        SamplerState samp;

        [shader("fragment")]
        float4 fragmentMain() : SV_Target { return tex.Sample(samp, float2(0, 0)); }
    """.trimIndent()

    @Test
    fun exposesEntryPointUserAttributes() {
        val result = compiler.compile(uniformsAndResources)
        val byName = result.entryPoints.associateBy { it.name }

        val topology = byName.getValue("vertexMain").attribute("topology")!!
        assertEquals(4, topology.intArg(0))
        assertEquals(64, topology.intArg(1))

        val scale = byName.getValue("fragmentMain").attribute("scale")!!
        assertEquals(1.5f, scale.floatArg(0))
    }

    @Test
    fun omitsBuiltinAttributesFromEntryPointAttributes() {
        val result = compiler.compile(uniformsAndResources)
        val byName = result.entryPoints.associateBy { it.name }

        // [shader] と [numthreads] はビルトインなのでユーザー属性には現れない
        assertEquals(emptyList<UserAttribute>(), byName.getValue("computeMain").attributes)
        assertEquals(listOf("topology"), byName.getValue("vertexMain").attributes.map { it.name })
    }

    @Test
    fun exposesGlobalConstantBufferBindingAndSize() {
        val result = compiler.compile(uniformsAndResources)

        // 暗黙のグローバル定数バッファがbinding 0を取り、リソースは1から並ぶ
        assertEquals(0, result.globalConstantBuffer.binding)
        assertEquals(1, result.parameters.first { it.name == "tex" }.bindingIndex)
        assertEquals(2, result.parameters.first { it.name == "samp" }.bindingIndex)

        // std140レイアウト: float amount @0 (4バイト), float3 tint @16 (12バイト)
        // 合計28バイトが16バイト境界に切り上げられて32になる
        assertEquals(16, result.parameters.first { it.name == "tint" }.uniformOffset)
        assertEquals(32, result.globalConstantBuffer.size)
    }

    @Test
    fun reportsZeroSizeWhenShaderHasNoUniforms() {
        val result = compiler.compile(resourcesOnly)

        assertEquals(0, result.globalConstantBuffer.size)
        // uniformが無いのでリソースが0から並ぶ
        assertEquals(0, result.parameters.first { it.name == "tex" }.bindingIndex)
        assertEquals(1, result.parameters.first { it.name == "samp" }.bindingIndex)
    }

    @Test
    fun parameterAttributesStillWorkAlongsideEntryPointAttributes() {
        val result = compiler.compile(
            """
            [__AttributeUsage(_AttributeTargets.Var)]
            struct labelAttribute { int value; };

            $attributeDecls

            [label(7)]
            uniform float amount;

            [scale(2.0)]
            [shader("fragment")]
            float4 fragmentMain() : SV_Target { return amount; }
            """.trimIndent()
        )

        assertEquals(7, result.parameters.first { it.name == "amount" }.attribute("label")!!.intArg(0))
        assertEquals(2f, result.entryPoints.first().attribute("scale")!!.floatArg(0))
        assertNull(result.entryPoints.first().attribute("label"))
    }
}
