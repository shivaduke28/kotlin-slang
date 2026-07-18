package com.shivaduke.kotlinslang

/** JNI境界の生の戻り値。[json]はリフレクション情報、[spirv]はエントリポイントごとのSPIR-V。 */
internal class NativeCompileResult(
    @JvmField val json: String,
    @JvmField val spirv: Array<ByteArray>,
)
