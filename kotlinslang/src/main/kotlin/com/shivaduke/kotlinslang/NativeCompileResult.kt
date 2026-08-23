package com.shivaduke.kotlinslang

/**
 * Raw return value from the JNI boundary. [json] carries the reflection data and [spirv]
 * holds one SPIR-V blob per entry point.
 */
internal class NativeCompileResult(
    @JvmField val json: String,
    @JvmField val spirv: Array<ByteArray>,
)
