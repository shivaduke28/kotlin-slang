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
 * Verifies the binding, descriptor set and size of the implicit global constant buffer.
 *
 * Reflection values are cross-checked against the OpDecorate (Binding / DescriptorSet)
 * instructions in the emitted SPIR-V. Asserting only that the buffer takes binding 0
 * would not distinguish a correct implementation from one that always returns 0, so a
 * case that pushes the buffer off binding 0 with explicit bindings is included.
 */
@RunWith(AndroidJUnit4::class)
class GlobalConstantBufferTest {

    private val compiler = SlangCompiler()

    /** Uniforms and resources, with binding assignment left to Slang. */
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
     * Bindings 0 and 1 are claimed explicitly by the resources, which pushes the implicit
     * global constant buffer to binding 2.
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

    /** No uniform parameters at all. */
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
        // std140: float amount at 0 (4 bytes), float3 tint at 16 (12 bytes);
        // 28 rounded up to a 16-byte boundary
        assertEquals(32, cb.size)
        // The constant buffer takes binding 0, so the resources start at 1
        assertEquals(1, result.parameters.first { it.name == "tex" }.bindingIndex)
        assertEquals(2, result.parameters.first { it.name == "samp" }.bindingIndex)
    }

    /**
     * The discriminating case: an implementation that always reports binding 0 for the
     * global constant buffer fails here.
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

            // Resource bindings come from the same path, so they must agree too
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

        // With no constant buffer the SPIR-V has no globalParams variable and the
        // resources start at binding 0
        val spirv = SpirvDecorations(result.entryPoints.first().spirv)
        assertNull(spirv.binding(GLOBAL_PARAMS))
        assertEquals(0, result.parameters.first { it.name == "tex" }.bindingIndex)
        assertEquals(0, spirv.binding("tex"))
        assertEquals(1, spirv.binding("samp"))
    }

    /** Guards against the comparisons above passing vacuously because the reader found nothing. */
    @Test
    fun spirvReaderResolvesNamedVariables() {
        val spirv = SpirvDecorations(compiler.compile(autoBindings).entryPoints.first().spirv)

        assertNotNull(spirv.binding(GLOBAL_PARAMS))
        assertNotNull(spirv.binding("tex"))
        assertNull(spirv.binding("nonexistent"))
    }

    /**
     * Minimal SPIR-V reader: collects OpName and OpDecorate so that the Binding and
     * DescriptorSet decorations of a named variable can be looked up.
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
                        // SPIR-V literal strings are NUL-terminated and NUL-padded to a word
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
        /** The variable name Slang gives the implicit global constant buffer. */
        const val GLOBAL_PARAMS = "globalParams"

        const val SPIRV_MAGIC = 0x07230203
        const val HEADER_WORDS = 5
        const val OP_NAME = 5
        const val OP_DECORATE = 71
        const val DECORATION_BINDING = 33
        const val DECORATION_DESCRIPTOR_SET = 34
    }
}
