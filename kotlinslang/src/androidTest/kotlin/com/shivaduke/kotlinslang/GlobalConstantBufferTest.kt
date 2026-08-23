package com.shivaduke.kotlinslang

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * 暗黙のグローバル定数バッファのbinding/space/sizeを検証する。
 *
 * リフレクション値は出力SPIR-VのOpDecorate（Binding / DescriptorSet）と突き合わせる。
 * 「binding 0を取る」だけを見る検証は、常に0を返す実装と正しい実装を区別できないため、
 * 明示bindingでグローバル定数バッファを0以外へずらすケースを含めている。
 */
@RunWith(AndroidJUnit4::class)
class GlobalConstantBufferTest {

    private val compiler = SlangCompiler()

    /** uniformとリソースを持ち、binding割り当てはSlangに任せるシェーダー。 */
    private val autoBindings = """
        uniform float amount;
        uniform float3 tint;
        Texture2D<float4> tex;
        SamplerState samp;

        [shader("fragment")]
        float4 fragmentMain() : SV_Target {
            return tex.Sample(samp, float2(0, 0)) * amount + float4(tint, 1);
        }
    """.trimIndent()

    /**
     * リソースにbinding 0/1を明示的に割り当て、暗黙のグローバル定数バッファを
     * binding 2へ押しやるシェーダー。
     */
    private val explicitBindings = """
        [[vk::binding(0, 0)]] Texture2D<float4> tex;
        [[vk::binding(1, 0)]] SamplerState samp;
        uniform float amount;
        uniform float3 tint;

        [shader("fragment")]
        float4 fragmentMain() : SV_Target {
            return tex.Sample(samp, float2(0, 0)) * amount + float4(tint, 1);
        }
    """.trimIndent()

    /** uniformを1つも持たないシェーダー。 */
    private val noUniforms = """
        Texture2D<float4> tex;
        SamplerState samp;

        [shader("fragment")]
        float4 fragmentMain() : SV_Target { return tex.Sample(samp, float2(0, 0)); }
    """.trimIndent()

    @Test
    fun reportsBindingAssignedBySlang() {
        val result = compiler.compile(autoBindings)
        val cb = result.globalConstantBuffer!!

        assertEquals(0, cb.binding)
        assertEquals(0, cb.space)
        // std140: float amount @0 (4バイト), float3 tint @16 (12バイト) → 28を16境界に切り上げ
        assertEquals(32, cb.size)
        // 定数バッファがbinding 0を取るのでリソースは1から並ぶ
        assertEquals(1, result.parameters.first { it.name == "tex" }.bindingIndex)
        assertEquals(2, result.parameters.first { it.name == "samp" }.bindingIndex)
    }

    /**
     * 本命の検証。グローバル定数バッファのbindingが常に0になる実装ではここで落ちる。
     */
    @Test
    fun reportsBindingShiftedByExplicitResourceBindings() {
        val result = compiler.compile(explicitBindings)
        val cb = result.globalConstantBuffer!!

        assertEquals(2, cb.binding)
        assertEquals(0, cb.space)
        assertEquals(32, cb.size)
        assertEquals(0, result.parameters.first { it.name == "tex" }.bindingIndex)
        assertEquals(1, result.parameters.first { it.name == "samp" }.bindingIndex)
    }

    @Test
    fun bindingAndSpaceMatchSpirvDecorations() {
        for (source in listOf(autoBindings, explicitBindings)) {
            val result = compiler.compile(source)
            val cb = result.globalConstantBuffer!!
            val spirv = SpirvDecorations(result.entryPoints.first().spirv)

            assertEquals(cb.binding, spirv.binding(GLOBAL_PARAMS))
            assertEquals(cb.space, spirv.descriptorSet(GLOBAL_PARAMS))

            // リソース側のbindingも同じ経路で一致することを確認する
            for (param in result.parameters.filter {
                    it.category == ParameterCategory.DescriptorTableSlot
                }) {
                assertEquals(param.name, param.bindingIndex, spirv.binding(param.name))
                assertEquals(param.name, param.bindingSpace, spirv.descriptorSet(param.name))
            }
        }
    }

    @Test
    fun reportsNullWhenShaderHasNoUniforms() {
        val result = compiler.compile(noUniforms)
        assertNull(result.globalConstantBuffer)

        // 定数バッファが無いのでSPIR-Vにも現れず、リソースがbinding 0から並ぶ
        val spirv = SpirvDecorations(result.entryPoints.first().spirv)
        assertNull(spirv.binding(GLOBAL_PARAMS))
        assertEquals(0, result.parameters.first { it.name == "tex" }.bindingIndex)
        assertEquals(0, spirv.binding("tex"))
        assertEquals(1, spirv.binding("samp"))
    }

    /** SpirvDecorations自体が動いていることの担保（上の突き合わせが空振りしないように）。 */
    @Test
    fun spirvReaderResolvesNamedVariables() {
        val spirv = SpirvDecorations(compiler.compile(autoBindings).entryPoints.first().spirv)

        assertNotNull(spirv.binding(GLOBAL_PARAMS))
        assertNotNull(spirv.binding("tex"))
        assertNull(spirv.binding("nonexistent"))
    }

    /**
     * SPIR-VバイナリからOpNameとOpDecorateを読み、名前付き変数のBinding /
     * DescriptorSetデコレーションを引けるようにする最小のリーダー。
     */
    private class SpirvDecorations(spirv: ByteArray) {
        private val names = mutableMapOf<Int, String>()
        private val decorations = mutableMapOf<Pair<Int, Int>, Int>()

        init {
            val buf = ByteBuffer.wrap(spirv).order(ByteOrder.LITTLE_ENDIAN)
            require(buf.int == SPIRV_MAGIC) { "not a SPIR-V module" }
            buf.position(HEADER_WORDS * 4)
            while (buf.remaining() >= 4) {
                val start = buf.position()
                val header = buf.int
                val opcode = header and 0xFFFF
                val wordCount = (header ushr 16) and 0xFFFF
                if (wordCount == 0 || start + wordCount * 4 > buf.limit()) break
                when (opcode) {
                    OP_NAME -> {
                        val target = buf.int
                        val bytes = ByteArray((wordCount - 2) * 4)
                        buf.get(bytes)
                        // SPIR-Vのリテラル文字列はNUL終端 + 4バイト境界までNULパディング
                        names[target] = String(bytes, Charsets.UTF_8).takeWhile { it != Char(0) }
                    }

                    OP_DECORATE -> if (wordCount >= 4) {
                        val target = buf.int
                        val decoration = buf.int
                        decorations[target to decoration] = buf.int
                    }
                }
                buf.position(start + wordCount * 4)
            }
        }

        private fun idOf(name: String): Int? =
            names.entries.firstOrNull { it.value == name }?.key

        fun binding(name: String): Int? = idOf(name)?.let { decorations[it to DECORATION_BINDING] }

        fun descriptorSet(name: String): Int? =
            idOf(name)?.let { decorations[it to DECORATION_DESCRIPTOR_SET] }
    }

    private companion object {
        /** Slangが暗黙のグローバル定数バッファに付ける変数名。 */
        const val GLOBAL_PARAMS = "globalParams"

        const val SPIRV_MAGIC = 0x07230203
        const val HEADER_WORDS = 5
        const val OP_NAME = 5
        const val OP_DECORATE = 71
        const val DECORATION_BINDING = 33
        const val DECORATION_DESCRIPTOR_SET = 34
    }
}
