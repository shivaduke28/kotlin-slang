package com.shivaduke.kotlinslang

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/**
 * エントリポイントのユーザー属性とパラメータのスカラ型がリフレクションから取れることを
 * 検証する。シェーダーはこのファイル内で完結させる。
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
    fun exposesScalarTypeOfUniformParameters() {
        val result = compiler.compile(
            """
            uniform float brightness;
            uniform int iterations;
            uniform bool enabled;
            uniform float3 tintColor;
            uniform int2 offset;
            Texture2D<float4> tex;

            [shader("fragment")]
            float4 fragmentMain() : SV_Target {
                float3 c = tintColor * brightness * iterations * offset.x;
                return enabled ? float4(c, 1) : tex.Load(int3(0, 0, 0));
            }
            """.trimIndent()
        )
        val byName = result.parameters.associateBy { it.name }

        // 属性が無くても素のスカラ型が区別できる（floatとintを取り違えない）
        assertEquals(ScalarType.Float32, byName.getValue("brightness").scalar)
        assertEquals(ScalarType.Int32, byName.getValue("iterations").scalar)
        assertEquals(ScalarType.Bool, byName.getValue("enabled").scalar)

        // ベクタでは要素のスカラ型
        assertEquals(ScalarType.Float32, byName.getValue("tintColor").scalar)
        assertEquals(TypeKind.Vector, byName.getValue("tintColor").kind)
        assertEquals(ScalarType.Int32, byName.getValue("offset").scalar)

        // リソースは値型ではないのでNone。要素型はresourceResult側で見る
        assertEquals(ScalarType.None, byName.getValue("tex").scalar)
        assertEquals(ScalarType.Float32, byName.getValue("tex").resourceResult!!.scalar)
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
