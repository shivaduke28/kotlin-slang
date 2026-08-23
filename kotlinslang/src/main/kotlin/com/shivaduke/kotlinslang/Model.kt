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

/** スカラ型。ベクタ・行列では要素のスカラ型を指す。 */
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

    /** スカラ型を持たない型（リソース、構造体など）。 */
    None("none");

    companion object {
        fun from(raw: String): ScalarType = entries.firstOrNull { it.raw == raw } ?: None
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
    val scalar: ScalarType,
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
    /** 値型のスカラ型。ベクタ・行列では要素のスカラ型。リソースや構造体では[ScalarType.None]。 */
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
    /** エントリポイント関数に付いたユーザー属性。意味づけは呼び出し側が行う。 */
    val attributes: List<UserAttribute>,
) {
    fun attribute(name: String): UserAttribute? = attributes.firstOrNull { it.name == name }
}

/**
 * Slangがバラのuniformパラメータ用に暗黙的に生成する定数バッファ。
 *
 * uniformパラメータを1つも宣言しないシェーダーではこの定数バッファ自体が存在せず、
 * [CompileResult.globalConstantBuffer]がnullになる。
 */
data class GlobalConstantBuffer(
    /** descriptor set内のbinding番号。 */
    val binding: Int,
    /** descriptor set番号。 */
    val space: Int,
    /** バイトサイズ。 */
    val size: Int,
)

data class CompileResult(
    val entryPoints: List<EntryPoint>,
    val parameters: List<ShaderParameter>,
    /** uniformパラメータを持たないシェーダーではnull。 */
    val globalConstantBuffer: GlobalConstantBuffer?,
    val diagnostics: String,
)

class SlangCompileException(
    val stage: String,
    val diagnostics: String,
) : Exception("Slang compilation failed at $stage: $diagnostics")
