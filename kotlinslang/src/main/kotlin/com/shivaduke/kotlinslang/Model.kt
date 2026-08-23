package com.shivaduke.kotlinslang

enum class ShaderStage(val raw: Int) {
    Vertex(1),
    Fragment(5),
    Compute(6),
    Unknown(0);

    companion object {
        fun from(raw: Int): ShaderStage = entries.firstOrNull { it.raw == raw } ?: Unknown
    }
}

/**
 * Parameter category reported by Slang reflection. On the SPIR-V target every resource
 * is a [DescriptorTableSlot].
 */
enum class ParameterCategory(val raw: String) {
    Uniform("uniform"),
    ConstantBuffer("constantBuffer"),
    DescriptorTableSlot("descriptorTableSlot"),
    ShaderResource("shaderResource"),
    UnorderedAccess("unorderedAccess"),
    SamplerState("samplerState"),
    Other("other");

    companion object {
        fun from(raw: String): ParameterCategory =
            entries.firstOrNull { it.raw == raw } ?: Other
    }
}

enum class TypeKind(val raw: String) {
    Scalar("scalar"),
    Vector("vector"),
    Matrix("matrix"),
    Resource("resource"),
    SamplerState("samplerState"),
    Struct("struct"),
    Array("array"),
    ConstantBuffer("constantBuffer"),
    ParameterBlock("parameterBlock"),
    Other("other");

    companion object {
        fun from(raw: String): TypeKind = entries.firstOrNull { it.raw == raw } ?: Other
    }
}

/** Scalar type. For vectors and matrices this is the element's scalar type. */
enum class ScalarType(val raw: String) {
    Float32("float32"),
    Float16("float16"),
    Float64("float64"),
    Int32("int32"),
    UInt32("uint32"),
    Int64("int64"),
    UInt64("uint64"),
    Int16("int16"),
    UInt16("uint16"),
    Int8("int8"),
    UInt8("uint8"),
    Bool("bool"),

    /** Types that have no scalar type, such as resources and structs. */
    None("none");

    companion object {
        fun from(raw: String): ScalarType = entries.firstOrNull { it.raw == raw } ?: None
    }
}

/** A user attribute such as `[range(min, max, default)]`. Arguments are numbers or strings. */
data class UserAttribute(
    val name: String,
    val args: List<Any>,
) {
    fun floatArg(index: Int): Float? = (args.getOrNull(index) as? Number)?.toFloat()
    fun intArg(index: Int): Int? = (args.getOrNull(index) as? Number)?.toInt()
}

/** Element type of a resource type such as `Texture2D<T>`. */
data class ResourceResultType(
    val kind: TypeKind,
    val components: Int,
    val scalar: ScalarType,
)

data class ShaderParameter(
    val name: String,
    val category: ParameterCategory,
    val bindingIndex: Int,
    /** Vulkan descriptor set number. */
    val bindingSpace: Int,
    val uniformOffset: Int,
    val kind: TypeKind,
    val size: Int,
    val alignment: Int,
    val elementSize: Int,
    /**
     * Scalar type of a value parameter; for vectors and matrices, the element's scalar
     * type. [ScalarType.None] for resources and structs, whose element type is reported
     * by [resourceResult] instead.
     */
    val scalar: ScalarType,
    val resourceResult: ResourceResultType?,
    val attributes: List<UserAttribute>,
) {
    fun attribute(name: String): UserAttribute? = attributes.firstOrNull { it.name == name }
}

data class EntryPoint(
    val name: String,
    val stage: ShaderStage,
    val spirv: ByteArray,
    /** User attributes on the entry point function. Interpreting them is the caller's job. */
    val attributes: List<UserAttribute>,
) {
    fun attribute(name: String): UserAttribute? = attributes.firstOrNull { it.name == name }
}

/**
 * The constant buffer Slang synthesises for loose uniform parameters.
 *
 * A shader that declares no uniform parameters has no such buffer, in which case
 * [CompileResult.globalConstantBuffer] is null.
 */
data class GlobalConstantBuffer(
    /** Binding number within the descriptor set. */
    val binding: Int,
    /** Descriptor set number. */
    val space: Int,
    /** Size in bytes. */
    val size: Int,
)

data class CompileResult(
    val entryPoints: List<EntryPoint>,
    val parameters: List<ShaderParameter>,
    /** Null for shaders that declare no uniform parameters. */
    val globalConstantBuffer: GlobalConstantBuffer?,
    val diagnostics: String,
)

class SlangCompileException(
    val stage: String,
    val diagnostics: String,
) : Exception("Slang compilation failed at $stage: $diagnostics")
