package com.shivaduke.kotlinslang

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Verifies that sources passed as additional modules can be imported by name from the main
 * source, and that declarations coming from them behave like local ones in reflection.
 * The shaders are inlined so the test is self-contained.
 */
@RunWith(AndroidJUnit4::class)
class AdditionalModulesTest {

    private val compiler = SlangCompiler()

    /** Attribute declarations and constants, the kind of thing a host shares across shaders. */
    private val decls = """
        [__AttributeUsage(_AttributeTargets.Var)]
        struct boundsAttribute { float min; float max; };

        [__AttributeUsage(_AttributeTargets.Var)]
        struct capacityAttribute { int count; };

        [__AttributeUsage(_AttributeTargets.Function)]
        struct gridAttribute { int columns; int rows; };

        static const int kColumns = 8;
        static const int kRows = 4;

        float3 halve(float3 v) { return v * 0.5; }
    """.trimIndent()

    private val standalone = """
        uniform float amount;

        [shader("fragment")]
        float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
            return float4(uv * amount, 0.0, 1.0);
        }
    """.trimIndent()

    private val importing = """
        import decls;

        [bounds(0.25, 4.0)]
        uniform float amount;

        [capacity(kColumns * kRows + 1)]
        uniform float3 tint;

        [grid(kColumns, kRows * 2)]
        [shader("fragment")]
        float4 fragmentMain(float2 uv : TEXCOORD) : SV_Target {
            return float4(halve(tint) * amount, 1.0);
        }
    """.trimIndent()

    private fun compileError(block: () -> Unit): SlangCompileException =
        assertThrows(SlangCompileException::class.java) { block() }

    @Test
    fun unimportedModuleDoesNotChangeTheResult() {
        // The module declares a uniform of its own, which would shift the layout if the
        // module leaked into the program.
        val unused = "$decls\nuniform float4 unusedModuleUniform;"

        val baseline = compiler.compile(standalone)
        val withModule = compiler.compile(standalone, emptyMap(), mapOf("decls" to unused))

        assertEquals(baseline.parameters, withModule.parameters)
        assertEquals(baseline.globalConstantBuffer, withModule.globalConstantBuffer)
        assertEquals(baseline.diagnostics, withModule.diagnostics)
        assertEquals(baseline.entryPoints.size, withModule.entryPoints.size)
        for ((expected, actual) in baseline.entryPoints.zip(withModule.entryPoints)) {
            assertEquals(expected.name, actual.name)
            assertEquals(expected.stage, actual.stage)
            assertEquals(expected.attributes, actual.attributes)
            assertArrayEquals(expected.spirv, actual.spirv)
        }
    }

    @Test
    fun emptyModulesMatchTheTwoArgumentOverload() {
        val baseline = compiler.compile(standalone)
        val explicit = compiler.compile(standalone, emptyMap(), emptyMap())

        assertEquals(baseline.parameters, explicit.parameters)
        assertArrayEquals(baseline.entryPoints.single().spirv, explicit.entryPoints.single().spirv)
    }

    @Test
    fun importedAttributesReportArgumentValues() {
        val result = compiler.compile(importing, emptyMap(), mapOf("decls" to decls))

        val bounds = result.parameters.first { it.name == "amount" }.attribute("bounds")!!
        assertEquals(2, bounds.args.size)
        assertEquals(0.25f, bounds.floatArg(0))
        assertEquals(4f, bounds.floatArg(1))

        val entryPoint = result.entryPoints.single()
        assertEquals("fragmentMain", entryPoint.name)
        assertTrue(entryPoint.spirv.isNotEmpty())
        val grid = entryPoint.attribute("grid")!!
        assertEquals(2, grid.args.size)
    }

    @Test
    fun importedConstantsAreFoldedInAttributeArguments() {
        val result = compiler.compile(importing, emptyMap(), mapOf("decls" to decls))

        val capacity = result.parameters.first { it.name == "tint" }.attribute("capacity")!!
        assertEquals(33, capacity.intArg(0))

        val grid = result.entryPoints.single().attribute("grid")!!
        assertEquals(8, grid.intArg(0))
        assertEquals(8, grid.intArg(1))
    }

    @Test
    fun importingTheSameModuleTwiceCompiles() {
        val once = compiler.compile(importing, emptyMap(), mapOf("decls" to decls))
        val twice = compiler.compile(
            "import decls;\n$importing",
            emptyMap(),
            mapOf("decls" to decls),
        )

        assertEquals(once.parameters, twice.parameters)
        assertEquals(once.entryPoints.single().attributes, twice.entryPoints.single().attributes)
    }

    @Test
    fun moduleCanImportAnEarlierModule() {
        val result = compiler.compile(
            """
            import derived;

            [capacity(kCells)]
            uniform float amount;

            [shader("fragment")]
            float4 fragmentMain() : SV_Target { return float4(amount); }
            """.trimIndent(),
            emptyMap(),
            linkedMapOf(
                "decls" to decls,
                "derived" to "__exported import decls;\nstatic const int kCells = kColumns * kRows;",
            ),
        )

        val capacity = result.parameters.first { it.name == "amount" }.attribute("capacity")!!
        assertEquals(32, capacity.intArg(0))
    }

    @Test
    fun macrosApplyToModules() {
        val result = compiler.compile(
            """
            import decls;

            [capacity(kScaled)]
            uniform float amount;

            [shader("fragment")]
            float4 fragmentMain() : SV_Target { return float4(amount); }
            """.trimIndent(),
            mapOf("SCALE" to "3"),
            mapOf("decls" to "$decls\nstatic const int kScaled = kColumns * SCALE;"),
        )

        val capacity = result.parameters.first { it.name == "amount" }.attribute("capacity")!!
        assertEquals(24, capacity.intArg(0))
    }

    @Test
    fun reportsModuleCompileErrors() {
        val e = compileError {
            compiler.compile(
                importing,
                emptyMap(),
                mapOf("decls" to "$decls\nstatic const int kBroken = undefined_module_symbol;"),
            )
        }

        assertEquals("load", e.stage)
        assertTrue(e.diagnostics, e.diagnostics.contains("undefined_module_symbol"))
        assertTrue(e.diagnostics, e.diagnostics.contains("decls.slang"))
    }

    @Test
    fun reportsModuleErrorsEvenWhenNotImported() {
        val e = compileError {
            compiler.compile(standalone, emptyMap(), mapOf("decls" to "this is not slang"))
        }

        assertEquals("load", e.stage)
        assertTrue(e.diagnostics, e.diagnostics.contains("decls.slang"))
    }

    @Test
    fun importingAnUnknownModuleFails() {
        val e = compileError {
            compiler.compile(importing, emptyMap(), mapOf("other" to decls))
        }

        assertEquals("load", e.stage)
        assertTrue(e.diagnostics, e.diagnostics.contains("decls"))
    }

    @Test
    fun rejectsInvalidModuleNames() {
        for (name in listOf("", "has space", "a/b", "1abc", "shader")) {
            assertThrows(IllegalArgumentException::class.java) {
                compiler.compile(standalone, emptyMap(), mapOf(name to decls))
            }
        }
    }
}
