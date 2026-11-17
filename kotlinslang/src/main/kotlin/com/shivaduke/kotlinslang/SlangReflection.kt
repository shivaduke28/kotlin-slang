package com.shivaduke.kotlinslang

/**
 * Base of the reflection classes, which mirror the reflection structs of the Slang API
 * (`slang::ProgramLayout`, `slang::TypeLayoutReflection`, ...).
 *
 * A reflection object is a view into the component type it was obtained from and is
 * owned by that component type's [session]; see [SlangSession] for lifetime. Two objects
 * are equal when they refer to the same native reflection object.
 */
abstract class SlangReflectionObject internal constructor(
    val session: SlangSession,
    private val nativeHandle: Long,
) {
    /** The native pointer, after checking that the session is still open. */
    internal val handle: Long
        get() {
            session.requireOpen()
            return nativeHandle
        }

    override fun equals(other: Any?): Boolean =
        other is SlangReflectionObject && other.javaClass == javaClass && other.nativeHandle == nativeHandle

    override fun hashCode(): Int = nativeHandle.hashCode()
}

private inline fun <T> Long.wrap(create: (Long) -> T): T? = if (this == 0L) null else create(this)

/** `slang::ProgramLayout` (`slang::ShaderReflection`): the layout of a linked program on one target. */
class SlangProgramLayout internal constructor(session: SlangSession, handle: Long) :
    SlangReflectionObject(session, handle) {

    /** `getParameterCount`: the number of global shader parameters. */
    val parameterCount: Int
        get() = SlangNative.programLayoutGetParameterCount(handle)

    /** `getParameterByIndex`. */
    fun getParameterByIndex(index: Int): SlangVariableLayoutReflection? =
        SlangNative.programLayoutGetParameterByIndex(handle, index)
            .wrap { SlangVariableLayoutReflection(session, it) }

    /** `getEntryPointCount`. */
    val entryPointCount: Long
        get() = SlangNative.programLayoutGetEntryPointCount(handle)

    /** `getEntryPointByIndex`. */
    fun getEntryPointByIndex(index: Int): SlangEntryPointReflection? =
        SlangNative.programLayoutGetEntryPointByIndex(handle, index)
            .wrap { SlangEntryPointReflection(session, it) }

    /** `findEntryPointByName`. */
    fun findEntryPointByName(name: String): SlangEntryPointReflection? =
        SlangNative.programLayoutFindEntryPointByName(handle, name)
            .wrap { SlangEntryPointReflection(session, it) }

    /**
     * `getGlobalConstantBufferBinding`. On SPIR-V targets this is always 0 regardless of
     * the real binding; read the binding from [globalParamsVarLayout] instead.
     */
    val globalConstantBufferBinding: Long
        get() = SlangNative.programLayoutGetGlobalConstantBufferBinding(handle)

    /**
     * `getGlobalConstantBufferSize`: byte size of the constant buffer Slang synthesises
     * for loose uniform parameters. May be [SLANG_UNKNOWN_SIZE] or [SLANG_UNBOUNDED_SIZE].
     */
    val globalConstantBufferSize: Long
        get() = SlangNative.programLayoutGetGlobalConstantBufferSize(handle)

    /** `getGlobalParamsTypeLayout`. */
    val globalParamsTypeLayout: SlangTypeLayoutReflection?
        get() = SlangNative.programLayoutGetGlobalParamsTypeLayout(handle)
            .wrap { SlangTypeLayoutReflection(session, it) }

    /** `getGlobalParamsVarLayout`. */
    val globalParamsVarLayout: SlangVariableLayoutReflection?
        get() = SlangNative.programLayoutGetGlobalParamsVarLayout(handle)
            .wrap { SlangVariableLayoutReflection(session, it) }
}

/** `slang::EntryPointReflection` (`slang::EntryPointLayout`): an entry point of a linked program. */
class SlangEntryPointReflection internal constructor(session: SlangSession, handle: Long) :
    SlangReflectionObject(session, handle) {

    /** `getName`. */
    val name: String?
        get() = SlangNative.entryPointReflectionGetName(handle)

    /** `getNameOverride`. */
    val nameOverride: String?
        get() = SlangNative.entryPointReflectionGetNameOverride(handle)

    /** `getParameterCount`: the number of parameters of the entry point function. */
    val parameterCount: Int
        get() = SlangNative.entryPointReflectionGetParameterCount(handle)

    /** `getFunction`. */
    val function: SlangFunctionReflection?
        get() = SlangNative.entryPointReflectionGetFunction(handle)
            .wrap { SlangFunctionReflection(session, it) }

    /** `getParameterByIndex`. */
    fun getParameterByIndex(index: Int): SlangVariableLayoutReflection? =
        SlangNative.entryPointReflectionGetParameterByIndex(handle, index)
            .wrap { SlangVariableLayoutReflection(session, it) }

    /** `getStage`. */
    val stage: SlangStage
        get() = SlangStage.from(SlangNative.entryPointReflectionGetStage(handle))

    /**
     * `getComputeThreadGroupSize`: the `[numthreads(...)]` sizes along the first
     * [axisCount] axes.
     */
    fun getComputeThreadGroupSize(axisCount: Int = 3): LongArray {
        val sizes = LongArray(axisCount)
        SlangNative.entryPointReflectionGetComputeThreadGroupSize(handle, sizes)
        return sizes
    }

    /** `getVarLayout`. */
    val varLayout: SlangVariableLayoutReflection?
        get() = SlangNative.entryPointReflectionGetVarLayout(handle)
            .wrap { SlangVariableLayoutReflection(session, it) }

    /** `getTypeLayout`. */
    val typeLayout: SlangTypeLayoutReflection?
        get() = SlangNative.entryPointReflectionGetTypeLayout(handle)
            .wrap { SlangTypeLayoutReflection(session, it) }

    /** `getResultVarLayout`. */
    val resultVarLayout: SlangVariableLayoutReflection?
        get() = SlangNative.entryPointReflectionGetResultVarLayout(handle)
            .wrap { SlangVariableLayoutReflection(session, it) }

    /** `hasDefaultConstantBuffer`. */
    fun hasDefaultConstantBuffer(): Boolean =
        SlangNative.entryPointReflectionHasDefaultConstantBuffer(handle)
}

/** `slang::FunctionReflection`. */
class SlangFunctionReflection internal constructor(session: SlangSession, handle: Long) :
    SlangReflectionObject(session, handle) {

    /** `getName`. */
    val name: String?
        get() = SlangNative.functionReflectionGetName(handle)

    /** `getReturnType`. */
    val returnType: SlangTypeReflection?
        get() = SlangNative.functionReflectionGetReturnType(handle)
            .wrap { SlangTypeReflection(session, it) }

    /** `getParameterCount`. */
    val parameterCount: Int
        get() = SlangNative.functionReflectionGetParameterCount(handle)

    /** `getParameterByIndex`. */
    fun getParameterByIndex(index: Int): SlangVariableReflection? =
        SlangNative.functionReflectionGetParameterByIndex(handle, index)
            .wrap { SlangVariableReflection(session, it) }

    /** `getUserAttributeCount`. */
    val userAttributeCount: Int
        get() = SlangNative.functionReflectionGetUserAttributeCount(handle)

    /** `getUserAttributeByIndex`. */
    fun getUserAttributeByIndex(index: Int): SlangAttribute? =
        SlangNative.functionReflectionGetUserAttributeByIndex(handle, index)
            .wrap { SlangAttribute(session, it) }
}

/** `slang::VariableReflection`: a variable, parameter or field declaration. */
class SlangVariableReflection internal constructor(session: SlangSession, handle: Long) :
    SlangReflectionObject(session, handle) {

    /** `getName`. */
    val name: String?
        get() = SlangNative.variableReflectionGetName(handle)

    /** `getType`. */
    val type: SlangTypeReflection?
        get() = SlangNative.variableReflectionGetType(handle)
            .wrap { SlangTypeReflection(session, it) }

    /** `getUserAttributeCount`. */
    val userAttributeCount: Int
        get() = SlangNative.variableReflectionGetUserAttributeCount(handle)

    /** `getUserAttributeByIndex`. */
    fun getUserAttributeByIndex(index: Int): SlangAttribute? =
        SlangNative.variableReflectionGetUserAttributeByIndex(handle, index)
            .wrap { SlangAttribute(session, it) }
}

/** `slang::VariableLayoutReflection`: a variable together with where it was laid out. */
class SlangVariableLayoutReflection internal constructor(session: SlangSession, handle: Long) :
    SlangReflectionObject(session, handle) {

    /** `getVariable`. */
    val variable: SlangVariableReflection?
        get() = SlangNative.variableLayoutReflectionGetVariable(handle)
            .wrap { SlangVariableReflection(session, it) }

    /** `getName`. */
    val name: String?
        get() = SlangNative.variableLayoutReflectionGetName(handle)

    /** `getTypeLayout`. */
    val typeLayout: SlangTypeLayoutReflection?
        get() = SlangNative.variableLayoutReflectionGetTypeLayout(handle)
            .wrap { SlangTypeLayoutReflection(session, it) }

    /** `getCategory`. */
    val category: SlangParameterCategory
        get() = SlangParameterCategory.from(SlangNative.variableLayoutReflectionGetCategory(handle))

    /** `getCategoryCount`. */
    val categoryCount: Int
        get() = SlangNative.variableLayoutReflectionGetCategoryCount(handle)

    /** `getCategoryByIndex`. */
    fun getCategoryByIndex(index: Int): SlangParameterCategory =
        SlangParameterCategory.from(SlangNative.variableLayoutReflectionGetCategoryByIndex(handle, index))

    /** `getOffset`. */
    fun getOffset(category: SlangParameterCategory = SlangParameterCategory.Uniform): Long =
        SlangNative.variableLayoutReflectionGetOffset(handle, category.raw)

    /** `getType`. */
    val type: SlangTypeReflection?
        get() = SlangNative.variableLayoutReflectionGetType(handle)
            .wrap { SlangTypeReflection(session, it) }

    /** `getBindingIndex`. */
    val bindingIndex: Int
        get() = SlangNative.variableLayoutReflectionGetBindingIndex(handle)

    /** `getBindingSpace()`. On SPIR-V targets this is the descriptor set number. */
    val bindingSpace: Int
        get() = SlangNative.variableLayoutReflectionGetBindingSpace(handle)

    /** `getBindingSpace(category)`. */
    fun getBindingSpace(category: SlangParameterCategory): Long =
        SlangNative.variableLayoutReflectionGetBindingSpaceForCategory(handle, category.raw)

    /** `getSemanticName`. */
    val semanticName: String?
        get() = SlangNative.variableLayoutReflectionGetSemanticName(handle)

    /** `getSemanticIndex`. */
    val semanticIndex: Long
        get() = SlangNative.variableLayoutReflectionGetSemanticIndex(handle)

    /** `getStage`. */
    val stage: SlangStage
        get() = SlangStage.from(SlangNative.variableLayoutReflectionGetStage(handle))
}

/** `slang::TypeReflection`. */
class SlangTypeReflection internal constructor(session: SlangSession, handle: Long) :
    SlangReflectionObject(session, handle) {

    /** `getKind`. */
    val kind: SlangTypeKind
        get() = SlangTypeKind.from(SlangNative.typeReflectionGetKind(handle))

    /** `getFieldCount`. Only struct types have fields. */
    val fieldCount: Int
        get() = SlangNative.typeReflectionGetFieldCount(handle)

    /** `getFieldByIndex`. */
    fun getFieldByIndex(index: Int): SlangVariableReflection? =
        SlangNative.typeReflectionGetFieldByIndex(handle, index)
            .wrap { SlangVariableReflection(session, it) }

    /** `isArray`. */
    fun isArray(): Boolean = SlangNative.typeReflectionIsArray(handle)

    /** `unwrapArray`. */
    fun unwrapArray(): SlangTypeReflection? =
        SlangNative.typeReflectionUnwrapArray(handle).wrap { SlangTypeReflection(session, it) }

    /** `getElementCount`: the element count of an array or vector type. */
    val elementCount: Long
        get() = SlangNative.typeReflectionGetElementCount(handle)

    /** `getElementType`. */
    val elementType: SlangTypeReflection?
        get() = SlangNative.typeReflectionGetElementType(handle)
            .wrap { SlangTypeReflection(session, it) }

    /** `getRowCount`. */
    val rowCount: Int
        get() = SlangNative.typeReflectionGetRowCount(handle)

    /** `getColumnCount`. */
    val columnCount: Int
        get() = SlangNative.typeReflectionGetColumnCount(handle)

    /** `getScalarType`. */
    val scalarType: SlangScalarType
        get() = SlangScalarType.from(SlangNative.typeReflectionGetScalarType(handle))

    /** `getResourceResultType`: the element type of a resource such as `Texture2D<T>`. */
    val resourceResultType: SlangTypeReflection?
        get() = SlangNative.typeReflectionGetResourceResultType(handle)
            .wrap { SlangTypeReflection(session, it) }

    /** `getName`. */
    val name: String?
        get() = SlangNative.typeReflectionGetName(handle)

    /** `getUserAttributeCount`. */
    val userAttributeCount: Int
        get() = SlangNative.typeReflectionGetUserAttributeCount(handle)

    /** `getUserAttributeByIndex`. */
    fun getUserAttributeByIndex(index: Int): SlangAttribute? =
        SlangNative.typeReflectionGetUserAttributeByIndex(handle, index)
            .wrap { SlangAttribute(session, it) }
}

/** `slang::TypeLayoutReflection`: a type together with its layout on a target. */
class SlangTypeLayoutReflection internal constructor(session: SlangSession, handle: Long) :
    SlangReflectionObject(session, handle) {

    /** `getType`. */
    val type: SlangTypeReflection?
        get() = SlangNative.typeLayoutReflectionGetType(handle)
            .wrap { SlangTypeReflection(session, it) }

    /** `getKind`. */
    val kind: SlangTypeKind
        get() = SlangTypeKind.from(SlangNative.typeLayoutReflectionGetKind(handle))

    /** `getSize`. May be [SLANG_UNKNOWN_SIZE] or [SLANG_UNBOUNDED_SIZE]. */
    fun getSize(category: SlangParameterCategory = SlangParameterCategory.Uniform): Long =
        SlangNative.typeLayoutReflectionGetSize(handle, category.raw)

    /** `getStride`: the size rounded up to the alignment. */
    fun getStride(category: SlangParameterCategory = SlangParameterCategory.Uniform): Long =
        SlangNative.typeLayoutReflectionGetStride(handle, category.raw)

    /** `getAlignment`. */
    fun getAlignment(category: SlangParameterCategory = SlangParameterCategory.Uniform): Int =
        SlangNative.typeLayoutReflectionGetAlignment(handle, category.raw)

    /** `getFieldCount`. Only struct types have fields. */
    val fieldCount: Int
        get() = SlangNative.typeLayoutReflectionGetFieldCount(handle)

    /** `getFieldByIndex`. */
    fun getFieldByIndex(index: Int): SlangVariableLayoutReflection? =
        SlangNative.typeLayoutReflectionGetFieldByIndex(handle, index)
            .wrap { SlangVariableLayoutReflection(session, it) }

    /** `findFieldIndexByName`. Returns -1 if there is no such field. */
    fun findFieldIndexByName(name: String): Long =
        SlangNative.typeLayoutReflectionFindFieldIndexByName(handle, name)

    /** `isArray`. */
    fun isArray(): Boolean = SlangNative.typeLayoutReflectionIsArray(handle)

    /** `unwrapArray`. */
    fun unwrapArray(): SlangTypeLayoutReflection? =
        SlangNative.typeLayoutReflectionUnwrapArray(handle)
            .wrap { SlangTypeLayoutReflection(session, it) }

    /** `getElementCount`. */
    val elementCount: Long
        get() = SlangNative.typeLayoutReflectionGetElementCount(handle)

    /**
     * `getElementStride`. Only meaningful for arrays and vectors; it is 0 for structured
     * buffers, whose stride is `elementTypeLayout.getStride()`.
     */
    fun getElementStride(category: SlangParameterCategory): Long =
        SlangNative.typeLayoutReflectionGetElementStride(handle, category.raw)

    /** `getElementTypeLayout`: the element of an array, buffer or constant buffer type. */
    val elementTypeLayout: SlangTypeLayoutReflection?
        get() = SlangNative.typeLayoutReflectionGetElementTypeLayout(handle)
            .wrap { SlangTypeLayoutReflection(session, it) }

    /** `getElementVarLayout`. */
    val elementVarLayout: SlangVariableLayoutReflection?
        get() = SlangNative.typeLayoutReflectionGetElementVarLayout(handle)
            .wrap { SlangVariableLayoutReflection(session, it) }

    /** `getContainerVarLayout`. */
    val containerVarLayout: SlangVariableLayoutReflection?
        get() = SlangNative.typeLayoutReflectionGetContainerVarLayout(handle)
            .wrap { SlangVariableLayoutReflection(session, it) }

    /** `getParameterCategory`. */
    val parameterCategory: SlangParameterCategory
        get() = SlangParameterCategory.from(SlangNative.typeLayoutReflectionGetParameterCategory(handle))

    /** `getCategoryCount`. */
    val categoryCount: Int
        get() = SlangNative.typeLayoutReflectionGetCategoryCount(handle)

    /** `getCategoryByIndex`. */
    fun getCategoryByIndex(index: Int): SlangParameterCategory =
        SlangParameterCategory.from(SlangNative.typeLayoutReflectionGetCategoryByIndex(handle, index))

    /** `getRowCount`. */
    val rowCount: Int
        get() = SlangNative.typeLayoutReflectionGetRowCount(handle)

    /** `getColumnCount`. */
    val columnCount: Int
        get() = SlangNative.typeLayoutReflectionGetColumnCount(handle)

    /** `getScalarType`. */
    val scalarType: SlangScalarType
        get() = SlangScalarType.from(SlangNative.typeLayoutReflectionGetScalarType(handle))

    /** `getResourceResultType`. */
    val resourceResultType: SlangTypeReflection?
        get() = SlangNative.typeLayoutReflectionGetResourceResultType(handle)
            .wrap { SlangTypeReflection(session, it) }

    /** `getName`. */
    val name: String?
        get() = SlangNative.typeLayoutReflectionGetName(handle)
}

/**
 * `slang::Attribute` (`slang::UserAttribute`): an attribute such as `[range(0, 1)]` on a
 * declaration, with its arguments evaluated.
 */
class SlangAttribute internal constructor(session: SlangSession, handle: Long) :
    SlangReflectionObject(session, handle) {

    /** `getName`. */
    val name: String?
        get() = SlangNative.attributeGetName(handle)

    /** `getArgumentCount`. */
    val argumentCount: Int
        get() = SlangNative.attributeGetArgumentCount(handle)

    /** `getArgumentType`. */
    fun getArgumentType(index: Int): SlangTypeReflection? =
        SlangNative.attributeGetArgumentType(handle, index).wrap { SlangTypeReflection(session, it) }

    /** `getArgumentValueInt`. Returns null if the argument is not an integer constant. */
    fun getArgumentValueInt(index: Int): Int? {
        val out = IntArray(1)
        return if (SlangNative.attributeGetArgumentValueInt(handle, index, out)) out[0] else null
    }

    /** `getArgumentValueFloat`. Returns null if the argument is not a floating-point constant. */
    fun getArgumentValueFloat(index: Int): Float? {
        val out = FloatArray(1)
        return if (SlangNative.attributeGetArgumentValueFloat(handle, index, out)) out[0] else null
    }

    /** `getArgumentValueString`. Returns null if the argument is not a string literal. */
    fun getArgumentValueString(index: Int): String? =
        SlangNative.attributeGetArgumentValueString(handle, index)
}
