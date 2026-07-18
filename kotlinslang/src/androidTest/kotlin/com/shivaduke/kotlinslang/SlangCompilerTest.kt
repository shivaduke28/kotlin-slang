package com.shivaduke.kotlinslang

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Arshesのテストシェーダーコーパス（assets/shaders）を実機でSPIR-Vにコンパイルし、
 * リフレクション情報がiOS(swift-slang)側と同じ内容で取れることを検証する。
 * シェーダーはArshesのSlangCompilerと同じくRangeAttribute.slangをprependする。
 */
@RunWith(AndroidJUnit4::class)
class SlangCompilerTest {

    private val compiler = SlangCompiler()

    private val macros = mapOf(
        "RESOLUTION_X" to "1920",
        "RESOLUTION_Y" to "1080",
        "DEPTH_RESOLUTION_X" to "256",
        "DEPTH_RESOLUTION_Y" to "192",
    )

    private fun readAsset(path: String): String =
        InstrumentationRegistry.getInstrumentation().context.assets.open(path)
            .bufferedReader().use { it.readText() }

    private fun compileShader(name: String): CompileResult {
        val prelude = readAsset("RangeAttribute.slang")
        val source = prelude + "\n" + readAsset("shaders/$name")
        return compiler.compile(source, macros)
    }

    @Test
    fun compilesWholeCorpus() {
        val corpus = InstrumentationRegistry.getInstrumentation().context.assets
            .list("shaders")!!.toList()
        assertTrue(corpus.isNotEmpty())
        for (name in corpus) {
            val result = compileShader(name)
            assertTrue("$name: no entry points", result.entryPoints.isNotEmpty())
            for (ep in result.entryPoints) {
                assertTrue("$name/${ep.name}: empty SPIR-V", ep.spirv.isNotEmpty())
                // SPIR-V magic number 0x07230203 (little endian)
                assertEquals("$name/${ep.name}: bad magic", 0x03, ep.spirv[0].toInt() and 0xff)
                assertEquals("$name/${ep.name}: bad magic", 0x02, ep.spirv[1].toInt() and 0xff)
                assertEquals("$name/${ep.name}: bad magic", 0x23, ep.spirv[2].toInt() and 0xff)
                assertEquals("$name/${ep.name}: bad magic", 0x07, ep.spirv[3].toInt() and 0xff)
            }
        }
    }

    @Test
    fun extractsUniformLayoutAndAttributes() {
        val result = compileShader("attributes.slang")

        val brightness = result.parameters.first { it.name == "brightness" }
        assertEquals(ParameterCategory.Uniform, brightness.category)
        assertEquals(0, brightness.uniformOffset)
        assertEquals(4, brightness.size)
        val range = brightness.attribute("range")!!
        assertEquals(0f, range.floatArg(0))
        assertEquals(1f, range.floatArg(1))
        assertEquals(0.5f, range.floatArg(2))

        val tintColor = result.parameters.first { it.name == "tintColor" }
        assertEquals(16, tintColor.uniformOffset)
        assertEquals(12, tintColor.size)
        assertEquals(16, tintColor.alignment)
        assertEquals(TypeKind.Vector, tintColor.kind)
        val rgb = tintColor.attribute("rgb")!!
        assertEquals(1f, rgb.floatArg(0))
        assertEquals(0.5f, rgb.floatArg(1))
        assertEquals(0.2f, rgb.floatArg(2))

        val enabled = result.parameters.first { it.name == "enabled" }
        assertEquals(1, enabled.attribute("toggle")!!.intArg(0))
    }

    @Test
    fun extractsResourceBindings() {
        val result = compileShader("camera_texture.slang")

        val cameraTex = result.parameters.first { it.name == "cameraTex" }
        assertEquals(ParameterCategory.DescriptorTableSlot, cameraTex.category)
        assertEquals(0, cameraTex.bindingIndex)
        assertEquals(0, cameraTex.bindingSpace)
        assertEquals(TypeKind.Resource, cameraTex.kind)
        assertEquals(3, cameraTex.resourceResult!!.components)
        assertEquals("float32", cameraTex.resourceResult!!.scalar)

        val samp = result.parameters.first { it.name == "samp" }
        assertEquals(TypeKind.SamplerState, samp.kind)
        assertEquals(1, samp.bindingIndex)
    }

    @Test
    fun extractsEntryPointStages() {
        val result = compileShader("gpu_particle.slang")
        val stages = result.entryPoints.associate { it.name to it.stage }
        assertEquals(ShaderStage.Compute, stages["initParticles"])
        assertEquals(ShaderStage.Vertex, stages["vertexMain"])
        assertEquals(ShaderStage.Fragment, stages["fragmentMain"])

        val particles = result.parameters.first { it.name == "particles" }
        assertEquals(32, particles.elementSize)
        assertEquals(64, particles.attribute("size")!!.intArg(0))
    }

    @Test
    fun reportsDiagnosticsOnError() {
        val e = try {
            compiler.compile("[shader(\"fragment\")]\nfloat4 f() : SV_Target { return undefined_symbol; }")
            null
        } catch (e: SlangCompileException) {
            e
        }
        assertTrue(e != null)
        assertTrue(e!!.diagnostics.contains("undefined"))
    }
}
