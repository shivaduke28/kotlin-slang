package com.shivaduke.kotlinslang

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Exercises the classes that mirror the Slang API: sessions, modules loaded from source
 * and imported by name, composing and linking, code generation and reflection. The
 * shaders are inlined so the test is self-contained.
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

    /** [importing] with the declarations inlined instead of imported. */
    private val importingSelfContained get() = decls + "\n" + importing.removePrefix("import decls;")

    private val twoStages = """
        struct Material { float3 albedo; float roughness; };
        uniform Material material;

        [shader("vertex")]
        float4 vertexMain(uint vid : SV_VertexID) : SV_Position { return float4(0, 0, 0, 1); }

        [shader("fragment")]
        float4 fragmentMain() : SV_Target { return float4(material.albedo, material.roughness); }

        float4 unmarked() : SV_Target { return float4(material.albedo, 1.0); }
    """.trimIndent()

    private fun createSession(macros: Map<String, String> = emptyMap()): SlangSession =
        global.createSession(
            SlangSessionDesc(
                targets = listOf(SlangTargetDesc(SlangCompileTarget.Spirv, global.findProfile("spirv_1_5"))),
                preprocessorMacros = macros,
            ),
        )

    private fun SlangSession.load(name: String, source: String): SlangModule =
        loadModuleFromSourceString(name, "$name.slang", source)

    /** Composes [module] with all the entry points it defines and links the result. */
    private fun SlangSession.link(module: SlangModule): SlangComponentType {
        val entryPoints = (0 until module.definedEntryPointCount).map { module.getDefinedEntryPoint(it)!! }
        return createCompositeComponentType(listOf(module) + entryPoints).link()
    }

    /** Loads [modules] in order, then loads [source] as `main` and runs [block] on its linked program. */
    private fun <T> linking(
        source: String,
        modules: Map<String, String> = emptyMap(),
        macros: Map<String, String> = emptyMap(),
        block: (SlangComponentType) -> T,
    ): T = createSession(macros).use { session ->
        for ((name, moduleSource) in modules) session.load(name, moduleSource)
        block(session.link(session.load("main", source)))
    }

    private fun SlangProgramLayout.parameter(name: String): SlangVariableLayoutReflection =
        (0 until parameterCount).map { getParameterByIndex(it)!! }.first { it.name == name }

    private fun SlangVariableLayoutReflection.attribute(name: String): SlangAttribute {
        val variable = variable!!
        return (0 until variable.userAttributeCount).map { variable.getUserAttributeByIndex(it)!! }
            .first { it.name == name }
    }

    private fun SlangFunctionReflection.attribute(name: String): SlangAttribute =
        (0 until userAttributeCount).map { getUserAttributeByIndex(it)!! }.first { it.name == name }

    /** Everything observable about a single-entry-point program, for comparing two compilations. */
    private fun snapshot(linked: SlangComponentType): List<Any?> {
        val layout = linked.getLayout()
        val parameters = (0 until layout.parameterCount).map { layout.getParameterByIndex(it)!! }
        return listOf(
            linked.getEntryPointCode(0, 0).toList(),
            layout.globalConstantBufferSize,
            parameters.map { it.name to it.getOffset() },
            parameters.map { p ->
                val variable = p.variable!!
                (0 until variable.userAttributeCount).map { variable.getUserAttributeByIndex(it)!!.name }
            },
        )
    }

    private fun compileError(block: () -> Unit): SlangCompileException =
        assertThrows(SlangCompileException::class.java) { block() }

    // --- Importing modules loaded from source ---------------------------------------

    @Test
    fun unimportedModuleDoesNotChangeTheResult() {
        // The module declares a uniform of its own, which would shift the layout if the
        // module leaked into the program.
        val unused = "$decls\nuniform float4 unusedModuleUniform;"

        val baseline = linking(standalone, block = ::snapshot)
        val withModule = linking(standalone, mapOf("decls" to unused), block = ::snapshot)

        assertEquals(baseline, withModule)
    }

    @Test
    fun importedAttributesReportArgumentValues() {
        linking(importing, mapOf("decls" to decls)) { linked ->
            val layout = linked.getLayout()

            val bounds = layout.parameter("amount").attribute("bounds")
            assertEquals(2, bounds.argumentCount)
            assertEquals(0.25f, bounds.getArgumentValueFloat(0))
            assertEquals(4f, bounds.getArgumentValueFloat(1))

            val entryPoint = layout.getEntryPointByIndex(0)!!
            assertEquals("fragmentMain", entryPoint.name)
            assertEquals(SlangStage.Fragment, entryPoint.stage)
            assertEquals(2, entryPoint.function!!.attribute("grid").argumentCount)
        }
    }

    @Test
    fun importedConstantsAreFoldedInAttributeArguments() {
        linking(importing, mapOf("decls" to decls)) { linked ->
            val layout = linked.getLayout()

            assertEquals(33, layout.parameter("tint").attribute("capacity").getArgumentValueInt(0))

            val grid = layout.getEntryPointByIndex(0)!!.function!!.attribute("grid")
            assertEquals(8, grid.getArgumentValueInt(0))
            assertEquals(8, grid.getArgumentValueInt(1))
        }
    }

    @Test
    fun importingTheSameModuleTwiceCompiles() {
        val once = linking(importing, mapOf("decls" to decls), block = ::snapshot)
        val twice = linking("import decls;\n$importing", mapOf("decls" to decls), block = ::snapshot)

        assertEquals(once, twice)
    }

    @Test
    fun moduleCanImportAnEarlierModule() {
        val source = """
            import derived;

            [capacity(kCells)]
            uniform float amount;

            [shader("fragment")]
            float4 fragmentMain() : SV_Target { return float4(amount); }
        """.trimIndent()
        val modules = linkedMapOf(
            "decls" to decls,
            "derived" to "__exported import decls;\nstatic const int kCells = kColumns * kRows;",
        )

        linking(source, modules) { linked ->
            val capacity = linked.getLayout().parameter("amount").attribute("capacity")
            assertEquals(32, capacity.getArgumentValueInt(0))
        }
    }

    @Test
    fun loadedModuleIsSharedByLaterModules() {
        createSession().use { session ->
            session.load("decls", decls)
            val first = session.link(session.load("first", importing))
            val second = session.link(
                session.load(
                    "second",
                    """
                    import decls;

                    [capacity(kRows)]
                    uniform float amount;

                    [shader("fragment")]
                    float4 fragmentMain() : SV_Target { return float4(amount); }
                    """.trimIndent(),
                ),
            )

            assertEquals(linking(importing, mapOf("decls" to decls), block = ::snapshot), snapshot(first))
            assertEquals(4, second.getLayout().parameter("amount").attribute("capacity").getArgumentValueInt(0))
            assertEquals(3L, session.loadedModuleCount)
        }
    }

    @Test
    fun macrosApplyToEveryModule() {
        val source = """
            import decls;

            [capacity(kScaled + SCALE)]
            uniform float amount;

            [shader("fragment")]
            float4 fragmentMain() : SV_Target { return float4(amount); }
        """.trimIndent()
        val modules = mapOf("decls" to "$decls\nstatic const int kScaled = kColumns * SCALE;")

        linking(source, modules, mapOf("SCALE" to "3")) { linked ->
            val capacity = linked.getLayout().parameter("amount").attribute("capacity")
            assertEquals(27, capacity.getArgumentValueInt(0))
        }
    }

    @Test
    fun reportsModuleCompileErrors() {
        createSession().use { session ->
            val diagnostics = StringBuilder()
            val e = compileError {
                session.loadModuleFromSourceString(
                    "decls",
                    "shared/decls.slang",
                    "$decls\nstatic const int kBroken = undefined_module_symbol;",
                    diagnostics,
                )
            }

            assertEquals("load", e.stage)
            assertTrue(e.diagnostics, e.diagnostics.contains("undefined_module_symbol"))
            assertTrue(e.diagnostics, e.diagnostics.contains("shared/decls.slang"))
            assertEquals(e.diagnostics, diagnostics.toString())
        }
    }

    @Test
    fun sessionStaysUsableAfterAFailedLoad() {
        createSession().use { session ->
            compileError { session.load("broken", "this is not slang") }

            session.load("decls", decls)
            val layout = session.link(session.load("main", importing)).getLayout()
            assertEquals(33, layout.parameter("tint").attribute("capacity").getArgumentValueInt(0))
        }
    }

    @Test
    fun importingAnUnknownModuleFails() {
        createSession().use { session ->
            session.load("other", decls)
            val e = compileError { session.load("main", importing) }

            assertEquals("load", e.stage)
            assertTrue(e.diagnostics, e.diagnostics.contains("decls"))
        }
    }

    @Test
    fun reloadingANameWithDifferentSourceFails() {
        createSession().use { session ->
            session.load("decls", decls)
            val e = compileError { session.load("decls", "$decls\nstatic const int kExtra = 1;") }

            assertEquals("load", e.stage)
        }
    }

    @Test
    fun loadModuleFindsAnAlreadyLoadedModule() {
        createSession().use { session ->
            val loaded = session.load("decls", decls)

            assertEquals("decls", session.loadModule("decls").name)
            assertEquals("decls", loaded.name)
            assertEquals("decls.slang", loaded.filePath)
            assertEquals("load", compileError { session.loadModule("missing_module") }.stage)
        }
    }

    // --- Modules, entry points, composing and code -----------------------------------

    @Test
    fun globalSessionReportsVersionAndProfiles() {
        assertTrue(global.buildTagString, global.buildTagString.isNotEmpty())
        assertTrue(global.findProfile("spirv_1_5") != SlangGlobalSession.SLANG_PROFILE_UNKNOWN)
        assertEquals(SlangGlobalSession.SLANG_PROFILE_UNKNOWN, global.findProfile("no_such_profile"))
    }

    @Test
    fun moduleListsItsEntryPoints() {
        createSession().use { session ->
            val module = session.load("main", twoStages)

            assertEquals(2, module.definedEntryPointCount)
            assertEquals("vertexMain", module.getDefinedEntryPoint(0)!!.functionReflection!!.name)
            assertEquals("fragmentMain", module.findEntryPointByName("fragmentMain")!!.functionReflection!!.name)
            assertNull(module.findEntryPointByName("missing"))
            assertNull(module.findEntryPointByName("unmarked"))
        }
    }

    @Test
    fun compositeChoosesWhichEntryPointsAreLinked() {
        createSession().use { session ->
            val module = session.load("main", twoStages)
            val fragment = module.findEntryPointByName("fragmentMain")!!
            val linked = session.createCompositeComponentType(listOf(module, fragment)).link()
            val layout = linked.getLayout()

            assertEquals(1L, layout.entryPointCount)
            assertEquals("fragmentMain", layout.getEntryPointByIndex(0)!!.name)
            assertNotNull(layout.findEntryPointByName("fragmentMain"))
            assertNull(layout.findEntryPointByName("vertexMain"))
            assertSpirv(linked.getEntryPointCode(0, 0))
            assertSpirv(linked.getTargetCode(0))
            assertEquals("emit", compileError { linked.getEntryPointCode(1, 0) }.stage)
        }
    }

    @Test
    fun findAndCheckEntryPointAcceptsAnUnmarkedFunction() {
        createSession().use { session ->
            val module = session.load("main", twoStages)
            val entryPoint = module.findAndCheckEntryPoint("unmarked", SlangStage.Fragment)
            val linked = session.createCompositeComponentType(listOf(module, entryPoint)).link()

            assertEquals(SlangStage.Fragment, linked.getLayout().getEntryPointByIndex(0)!!.stage)
            assertSpirv(linked.getEntryPointCode(0, 0))
            assertEquals(
                "entryPoint",
                compileError { module.findAndCheckEntryPoint("missing", SlangStage.Fragment) }.stage,
            )
        }
    }

    @Test
    fun matchesSlangCompiler() {
        val expected = SlangCompiler().compile(importingSelfContained)

        linking(importingSelfContained) { linked ->
            assertArrayEquals(expected.entryPoints.single().spirv, linked.getEntryPointCode(0, 0))
            val layout = linked.getLayout()
            assertEquals(expected.parameters.map { it.name }, (0 until layout.parameterCount).map { layout.getParameterByIndex(it)!!.name })
            assertEquals(expected.globalConstantBuffer!!.size.toLong(), layout.globalConstantBufferSize)
        }
    }

    // --- Reflection --------------------------------------------------------------------

    @Test
    fun reflectsStructFieldsAndLayout() {
        linking(twoStages) { linked ->
            val layout = linked.getLayout()
            val material = layout.parameter("material")
            val typeLayout = material.typeLayout!!

            assertEquals(SlangParameterCategory.Uniform, material.category)
            assertEquals(SlangTypeKind.Struct, typeLayout.kind)
            assertEquals("Material", typeLayout.name)
            assertEquals(16L, typeLayout.getSize())
            assertEquals(2, typeLayout.fieldCount)
            assertEquals(1L, typeLayout.findFieldIndexByName("roughness"))
            assertEquals(-1L, typeLayout.findFieldIndexByName("missing"))

            val albedo = typeLayout.getFieldByIndex(0)!!
            assertEquals("albedo", albedo.name)
            assertEquals(0L, albedo.getOffset())
            assertEquals(SlangTypeKind.Vector, albedo.typeLayout!!.kind)
            assertEquals(SlangScalarType.Float32, albedo.type!!.elementType!!.scalarType)
            assertEquals(3L, albedo.type!!.elementCount)

            val roughness = typeLayout.getFieldByIndex(1)!!
            assertEquals(12L, roughness.getOffset())
            assertEquals(SlangScalarType.Float32, roughness.typeLayout!!.scalarType)
            assertEquals(roughness.variable, typeLayout.type!!.getFieldByIndex(1))

            assertEquals(SlangTypeKind.ConstantBuffer, layout.globalParamsTypeLayout!!.kind)
            assertEquals(16L, layout.globalConstantBufferSize)
            assertEquals(0, layout.globalParamsVarLayout!!.bindingSpace)
        }
    }

    @Test
    fun reflectsComputeThreadGroupSize() {
        val source = """
            RWStructuredBuffer<float> values;

            [shader("compute")]
            [numthreads(8, 4, 2)]
            void computeMain(uint3 id : SV_DispatchThreadID) { values[id.x] = 1.0; }
        """.trimIndent()

        linking(source) { linked ->
            val layout = linked.getLayout()
            val entryPoint = layout.getEntryPointByIndex(0)!!

            assertEquals(SlangStage.Compute, entryPoint.stage)
            assertArrayEquals(longArrayOf(8, 4, 2), entryPoint.getComputeThreadGroupSize())
            val values = layout.parameter("values")
            assertEquals(SlangParameterCategory.DescriptorTableSlot, values.category)
            assertEquals(SlangTypeKind.Resource, values.typeLayout!!.kind)
            assertEquals(4L, values.typeLayout!!.elementTypeLayout!!.getStride())
        }
    }

    // --- Lifetime ----------------------------------------------------------------------

    @Test
    fun closedSessionRejectsFurtherUse() {
        val session = createSession()
        val module = session.load("main", standalone)
        val linked = session.link(module)
        val layout = linked.getLayout()
        val parameter = layout.getParameterByIndex(0)!!
        session.close()
        session.close()

        assertThrows(IllegalStateException::class.java) { session.load("other", standalone) }
        assertThrows(IllegalStateException::class.java) { module.name }
        assertThrows(IllegalStateException::class.java) { linked.getEntryPointCode(0, 0) }
        assertThrows(IllegalStateException::class.java) { layout.parameterCount }
        assertThrows(IllegalStateException::class.java) { parameter.name }
    }

    @Test
    fun sessionOutlivesItsClosedGlobalSession() {
        val ownGlobal = SlangGlobalSession.create()
        val session = ownGlobal.createSession(
            SlangSessionDesc(listOf(SlangTargetDesc(SlangCompileTarget.Spirv, ownGlobal.findProfile("spirv_1_5")))),
        )
        ownGlobal.close()

        session.use {
            assertSpirv(it.link(it.load("main", standalone)).getEntryPointCode(0, 0))
        }
        assertThrows(IllegalStateException::class.java) { ownGlobal.findProfile("spirv_1_5") }
    }

    private fun assertSpirv(code: ByteArray) {
        // SPIR-V magic number 0x07230203 (little endian)
        assertArrayEquals(byteArrayOf(0x03, 0x02, 0x23, 0x07), code.copyOf(4))
    }

    private companion object {
        /** Creating a global session is expensive, so the tests share one. */
        val global: SlangGlobalSession by lazy { SlangGlobalSession.create() }
    }
}
