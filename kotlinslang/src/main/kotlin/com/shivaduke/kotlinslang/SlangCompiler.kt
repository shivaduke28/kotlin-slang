package com.shivaduke.kotlinslang

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode

/**
 * Compiles a single Slang source to SPIR-V 1.5 and collects the reflection data most
 * hosts need into plain data classes.
 *
 * This is a convenience built on the classes that mirror the Slang API
 * ([SlangGlobalSession], [SlangSession], [SlangModule], [SlangComponentType] and the
 * reflection classes). Use those directly to load several modules that import one
 * another, to choose which entry points to link, to target something other than SPIR-V,
 * or to read reflection data this class does not collect.
 *
 * Slang's global session is not thread-safe, so this class must be used from a single
 * thread, or calls must be serialized by the application.
 */
class SlangCompiler {

    /**
     * Compiles [source] and returns the SPIR-V for every entry point along with the
     * reflection data.
     *
     * @throws SlangCompileException on compilation failure, carrying Slang diagnostics
     */
    fun compile(source: String, macros: Map<String, String> = emptyMap()): CompileResult {
        val global = globalSession
        val desc = SlangSessionDesc(
            targets = listOf(SlangTargetDesc(SlangCompileTarget.Spirv, global.findProfile("spirv_1_5"))),
            preprocessorMacros = macros,
        )
        return global.createSession(desc).use { session -> compile(session, source) }
    }

    private fun compile(session: SlangSession, source: String): CompileResult {
        val diagnostics = StringBuilder()
        val module = session.loadModuleFromSourceString("shader", "shader.slang", source, diagnostics)

        val entryPoints = (0 until module.definedEntryPointCount).mapNotNull { module.getDefinedEntryPoint(it) }
        val linked = session.createCompositeComponentType(listOf(module) + entryPoints).link()
        val layout = linked.getLayout(0)

        val compiledEntryPoints = entryPoints.indices.map { index ->
            val code = linked.getEntryPointCode(index.toLong(), 0)
            val reflection = layout.getEntryPointByIndex(index)
            EntryPoint(
                name = reflection?.name.orEmpty(),
                stage = ShaderStage.from(reflection?.stage?.raw ?: 0),
                spirv = code,
                attributes = userAttributes(reflection?.function),
            )
        }

        return CompileResult(
            entryPoints = compiledEntryPoints,
            parameters = (0 until layout.parameterCount).map { parameter(layout.getParameterByIndex(it)!!) },
            globalConstantBuffer = globalConstantBuffer(layout),
            diagnostics = diagnostics.toString(),
        )
    }

    /**
     * The implicit constant buffer Slang synthesises for loose uniform parameters, or null
     * when the shader declares none.
     *
     * The binding comes from the global params var layout, which also carries the
     * descriptor set number. `ProgramLayout::getGlobalConstantBufferBinding` does not work
     * on this target: it looks up `LayoutResourceKind::ConstantBuffer`, the GLSL/SPIR-V
     * layout rules map constant buffers to `DescriptorTableSlot`, so the lookup always
     * misses and it returns 0 regardless of the real binding.
     */
    private fun globalConstantBuffer(layout: SlangProgramLayout): GlobalConstantBuffer? {
        val globalsVar = layout.globalParamsVarLayout
        if (layout.globalParamsTypeLayout?.kind != SlangTypeKind.ConstantBuffer || globalsVar == null) return null

        val size = layout.globalConstantBufferSize
        if (size == SLANG_UNKNOWN_SIZE || size == SLANG_UNBOUNDED_SIZE) {
            throw SlangCompileException(
                "layout",
                "global constant buffer size is unbounded or could not be resolved",
            )
        }
        return GlobalConstantBuffer(
            binding = globalsVar.bindingIndex,
            space = globalsVar.bindingSpace,
            size = size.toInt(),
        )
    }

    private fun parameter(param: SlangVariableLayoutReflection): ShaderParameter {
        val typeLayout = param.typeLayout
        // getElementStride() returns 0 for structured buffers; it only handles arrays and
        // vectors. The element's own stride is its size rounded up to its alignment.
        val element = typeLayout?.elementTypeLayout
        return ShaderParameter(
            name = param.name.orEmpty(),
            category = category(param.category),
            bindingIndex = param.bindingIndex,
            bindingSpace = param.bindingSpace,
            uniformOffset = param.getOffset().toInt(),
            kind = typeLayout?.let { kind(it.kind) } ?: TypeKind.Other,
            size = typeLayout?.getSize()?.toInt() ?: 0,
            alignment = typeLayout?.getAlignment() ?: 0,
            elementSize = element?.getSize()?.toInt() ?: 0,
            elementStride = element?.getStride()?.toInt() ?: 0,
            scalar = scalarOf(typeLayout?.type),
            resourceResult = typeLayout
                ?.takeIf { it.kind == SlangTypeKind.Resource }
                ?.type?.resourceResultType
                ?.let(::resourceResult),
            attributes = userAttributes(param.variable),
        )
    }

    private fun resourceResult(result: SlangTypeReflection): ResourceResultType {
        val isVector = result.kind == SlangTypeKind.Vector
        val scalar = if (isVector) result.elementType else result
        return ResourceResultType(
            kind = kind(result.kind),
            components = if (isVector) result.elementCount.toInt() else 1,
            scalar = scalar?.let { scalar(it.scalarType) } ?: ScalarType.None,
        )
    }

    /**
     * Scalar type behind a value type: the type itself for scalars, the element type for
     * vectors and matrices, none for anything else (resources, structs, ...).
     */
    private fun scalarOf(type: SlangTypeReflection?): ScalarType = when (type?.kind) {
        SlangTypeKind.Vector, SlangTypeKind.Matrix ->
            type.elementType?.let { scalar(it.scalarType) } ?: ScalarType.None
        SlangTypeKind.Scalar -> scalar(type.scalarType)
        else -> ScalarType.None
    }

    private fun userAttributes(function: SlangFunctionReflection?): List<UserAttribute> =
        if (function == null) emptyList()
        else (0 until function.userAttributeCount).mapNotNull { function.getUserAttributeByIndex(it) }
            .map(::userAttribute)

    private fun userAttributes(variable: SlangVariableReflection?): List<UserAttribute> =
        if (variable == null) emptyList()
        else (0 until variable.userAttributeCount).mapNotNull { variable.getUserAttributeByIndex(it) }
            .map(::userAttribute)

    private fun userAttribute(attribute: SlangAttribute) = UserAttribute(
        name = attribute.name.orEmpty(),
        args = (0 until attribute.argumentCount).map { index ->
            attribute.getArgumentValueFloat(index)?.let(::number)
                ?: attribute.getArgumentValueInt(index)
                ?: attribute.getArgumentValueString(index).orEmpty()
        },
    )

    /**
     * A float argument as the number [UserAttribute.args] has always carried: the value at
     * six significant digits, as an [Int] when that is a whole number below a million and
     * as a [Double] otherwise. This is what printing with C's `%g` and parsing the text
     * back as JSON yields, which is how arguments used to cross the JNI boundary.
     */
    private fun number(value: Float): Number {
        val exact = value.toDouble()
        if (value.isNaN() || value.isInfinite()) return exact
        if (exact == 0.0) return 0

        val rounded = BigDecimal(exact).round(MathContext(6, RoundingMode.HALF_EVEN))
        val exponent = rounded.precision() - rounded.scale() - 1
        val isWhole = rounded.stripTrailingZeros().scale() <= 0
        return if (isWhole && exponent in 0 until 6) rounded.toInt() else rounded.toDouble()
    }

    private fun category(category: SlangParameterCategory): ParameterCategory = when (category) {
        SlangParameterCategory.ConstantBuffer -> ParameterCategory.ConstantBuffer
        SlangParameterCategory.ShaderResource -> ParameterCategory.ShaderResource
        SlangParameterCategory.UnorderedAccess -> ParameterCategory.UnorderedAccess
        SlangParameterCategory.SamplerState -> ParameterCategory.SamplerState
        SlangParameterCategory.Uniform -> ParameterCategory.Uniform
        SlangParameterCategory.DescriptorTableSlot -> ParameterCategory.DescriptorTableSlot
        else -> ParameterCategory.Other
    }

    private fun kind(kind: SlangTypeKind): TypeKind = when (kind) {
        SlangTypeKind.Scalar -> TypeKind.Scalar
        SlangTypeKind.Vector -> TypeKind.Vector
        SlangTypeKind.Matrix -> TypeKind.Matrix
        SlangTypeKind.Resource -> TypeKind.Resource
        SlangTypeKind.SamplerState -> TypeKind.SamplerState
        SlangTypeKind.Struct -> TypeKind.Struct
        SlangTypeKind.Array -> TypeKind.Array
        SlangTypeKind.ConstantBuffer -> TypeKind.ConstantBuffer
        SlangTypeKind.ParameterBlock -> TypeKind.ParameterBlock
        else -> TypeKind.Other
    }

    private fun scalar(scalar: SlangScalarType): ScalarType = when (scalar) {
        SlangScalarType.Float32 -> ScalarType.Float32
        SlangScalarType.Float16 -> ScalarType.Float16
        SlangScalarType.Float64 -> ScalarType.Float64
        SlangScalarType.Int32 -> ScalarType.Int32
        SlangScalarType.UInt32 -> ScalarType.UInt32
        SlangScalarType.Int64 -> ScalarType.Int64
        SlangScalarType.UInt64 -> ScalarType.UInt64
        SlangScalarType.Int16 -> ScalarType.Int16
        SlangScalarType.UInt16 -> ScalarType.UInt16
        SlangScalarType.Int8 -> ScalarType.Int8
        SlangScalarType.UInt8 -> ScalarType.UInt8
        SlangScalarType.Bool -> ScalarType.Bool
        else -> ScalarType.None
    }

    private companion object {
        /** Shared by every instance; creating a global session is expensive. */
        val globalSession: SlangGlobalSession by lazy { SlangGlobalSession.create() }
    }
}
