package com.shivaduke.kotlinslang

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Verifies that modules loaded into a [SlangSession] can be imported by name from modules
 * loaded after them, and that declarations coming from them behave like local ones in
 * reflection. The shaders are inlined so the test is self-contained.
 */
@RunWith(AndroidJUnit4::class)
class SlangSessionTest {

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

    /** Loads [modules] in order, then compiles [source] as the module `main`. */
    private fun compile(
        source: String,
        modules: Map<String, String> = emptyMap(),
        macros: Map<String, String> = emptyMap(),
    ): CompileResult = SlangSession(macros).use { session ->
        for ((name, moduleSource) in modules) session.loadModule(name, moduleSource)
        session.loadModule("main", source).compile()
    }

    private fun assertSameOutput(expected: CompileResult, actual: CompileResult) {
        assertEquals(expected.parameters, actual.parameters)
        assertEquals(expected.globalConstantBuffer, actual.globalConstantBuffer)
        assertEquals(expected.diagnostics, actual.diagnostics)
        assertEquals(expected.entryPoints.size, actual.entryPoints.size)
        for ((e, a) in expected.entryPoints.zip(actual.entryPoints)) {
            assertEquals(e.name, a.name)
            assertEquals(e.stage, a.stage)
            assertEquals(e.attributes, a.attributes)
            assertArrayEquals(e.spirv, a.spirv)
        }
    }

    @Test
    fun matchesSlangCompilerForStandaloneSource() {
        assertSameOutput(SlangCompiler().compile(standalone), compile(standalone))
    }

    @Test
    fun unimportedModuleDoesNotChangeTheResult() {
        // The module declares a uniform of its own, which would shift the layout if the
        // module leaked into the program.
        val unused = "$decls\nuniform float4 unusedModuleUniform;"

        assertSameOutput(compile(standalone), compile(standalone, mapOf("decls" to unused)))
    }

    @Test
    fun importedAttributesReportArgumentValues() {
        val result = compile(importing, mapOf("decls" to decls))

        val bounds = result.parameters.first { it.name == "amount" }.attribute("bounds")!!
        assertEquals(2, bounds.args.size)
        assertEquals(0.25f, bounds.floatArg(0))
        assertEquals(4f, bounds.floatArg(1))

        val entryPoint = result.entryPoints.single()
        assertEquals("fragmentMain", entryPoint.name)
        assertTrue(entryPoint.spirv.isNotEmpty())
        assertEquals(2, entryPoint.attribute("grid")!!.args.size)
    }

    @Test
    fun importedConstantsAreFoldedInAttributeArguments() {
        val result = compile(importing, mapOf("decls" to decls))

        val capacity = result.parameters.first { it.name == "tint" }.attribute("capacity")!!
        assertEquals(33, capacity.intArg(0))

        val grid = result.entryPoints.single().attribute("grid")!!
        assertEquals(8, grid.intArg(0))
        assertEquals(8, grid.intArg(1))
    }

    @Test
    fun importingTheSameModuleTwiceCompiles() {
        val once = compile(importing, mapOf("decls" to decls))
        val twice = compile("import decls;\n$importing", mapOf("decls" to decls))

        assertSameOutput(once, twice)
    }

    @Test
    fun moduleCanImportAnEarlierModule() {
        val result = compile(
            """
            import derived;

            [capacity(kCells)]
            uniform float amount;

            [shader("fragment")]
            float4 fragmentMain() : SV_Target { return float4(amount); }
            """.trimIndent(),
            linkedMapOf(
                "decls" to decls,
                "derived" to "__exported import decls;\nstatic const int kCells = kColumns * kRows;",
            ),
        )

        val capacity = result.parameters.first { it.name == "amount" }.attribute("capacity")!!
        assertEquals(32, capacity.intArg(0))
    }

    @Test
    fun loadedModuleIsSharedByLaterModules() {
        SlangSession().use { session ->
            session.loadModule("decls", decls)
            val first = session.loadModule("first", importing).compile()
            val second = session.loadModule(
                "second",
                """
                import decls;

                [capacity(kRows)]
                uniform float amount;

                [shader("fragment")]
                float4 fragmentMain() : SV_Target { return float4(amount); }
                """.trimIndent(),
            ).compile()

            assertSameOutput(compile(importing, mapOf("decls" to decls)), first)
            val capacity = second.parameters.single().attribute("capacity")!!
            assertEquals(4, capacity.intArg(0))
        }
    }

    @Test
    fun moduleCanBeCompiledMoreThanOnce() {
        SlangSession().use { session ->
            session.loadModule("decls", decls)
            val module = session.loadModule("main", importing)

            assertEquals("main", module.name)
            assertSameOutput(module.compile(), module.compile())
        }
    }

    @Test
    fun macrosApplyToEveryModule() {
        val result = compile(
            """
            import decls;

            [capacity(kScaled + SCALE)]
            uniform float amount;

            [shader("fragment")]
            float4 fragmentMain() : SV_Target { return float4(amount); }
            """.trimIndent(),
            mapOf("decls" to "$decls\nstatic const int kScaled = kColumns * SCALE;"),
            mapOf("SCALE" to "3"),
        )

        val capacity = result.parameters.first { it.name == "amount" }.attribute("capacity")!!
        assertEquals(27, capacity.intArg(0))
    }

    @Test
    fun reportsModuleCompileErrors() {
        SlangSession().use { session ->
            val e = compileError {
                session.loadModule(
                    "decls",
                    "$decls\nstatic const int kBroken = undefined_module_symbol;",
                )
            }

            assertEquals("load", e.stage)
            assertTrue(e.diagnostics, e.diagnostics.contains("undefined_module_symbol"))
            assertTrue(e.diagnostics, e.diagnostics.contains("decls.slang"))
        }
    }

    @Test
    fun reportsErrorsAgainstTheGivenPath() {
        SlangSession().use { session ->
            val e = compileError {
                session.loadModule("decls", "this is not slang", path = "shared/decls.slang")
            }

            assertTrue(e.diagnostics, e.diagnostics.contains("shared/decls.slang"))
        }
    }

    @Test
    fun sessionStaysUsableAfterAFailedLoad() {
        SlangSession().use { session ->
            compileError { session.loadModule("broken", "this is not slang") }

            session.loadModule("decls", decls)
            val result = session.loadModule("main", importing).compile()
            assertEquals(33, result.parameters.first { it.name == "tint" }.attribute("capacity")!!.intArg(0))
        }
    }

    @Test
    fun importingAnUnknownModuleFails() {
        val e = compileError { compile(importing, mapOf("other" to decls)) }

        assertEquals("load", e.stage)
        assertTrue(e.diagnostics, e.diagnostics.contains("decls"))
    }

    @Test
    fun reloadingANameWithDifferentSourceFails() {
        SlangSession().use { session ->
            session.loadModule("decls", decls)
            val e = compileError { session.loadModule("decls", "$decls\nstatic const int kExtra = 1;") }

            assertEquals("load", e.stage)
        }
    }

    @Test
    fun closedSessionRejectsFurtherUse() {
        val session = SlangSession()
        val module = session.loadModule("main", standalone)
        session.close()
        session.close()

        assertThrows(IllegalStateException::class.java) { session.loadModule("other", standalone) }
        assertThrows(IllegalStateException::class.java) { module.compile() }
    }
}
