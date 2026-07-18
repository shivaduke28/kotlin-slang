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

/** Slangリフレクションのパラメータカテゴリ。SPIR-Vターゲットではリソースはすべて[DescriptorTableSlot]になる。 */
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

/** `[range(min, max, default)]` のようなユーザー属性。引数は数値または文字列。 */
data class UserAttribute(
    val name: String,
    val args: List<Any>,
) {
    fun floatArg(index: Int): Float? = (args.getOrNull(index) as? Number)?.toFloat()
    fun intArg(index: Int): Int? = (args.getOrNull(index) as? Number)?.toInt()
}

/** リソース型（Texture2D<T>等）の要素型情報。 */
data class ResourceResultType(
    val kind: TypeKind,
    val components: Int,
    val scalar: String,
)

data class ShaderParameter(
    val name: String,
    val category: ParameterCategory,
    val bindingIndex: Int,
    /** Vulkanのdescriptor set番号。 */
    val bindingSpace: Int,
    val uniformOffset: Int,
    val kind: TypeKind,
    val size: Int,
    val alignment: Int,
    val elementSize: Int,
    val resourceResult: ResourceResultType?,
    val attributes: List<UserAttribute>,
) {
    fun attribute(name: String): UserAttribute? = attributes.firstOrNull { it.name == name }
}

data class EntryPoint(
    val name: String,
    val stage: ShaderStage,
    val spirv: ByteArray,
)

data class CompileResult(
    val entryPoints: List<EntryPoint>,
    val parameters: List<ShaderParameter>,
    val diagnostics: String,
)

class SlangCompileException(
    val stage: String,
    val diagnostics: String,
) : Exception("Slang compilation failed at $stage: $diagnostics")
