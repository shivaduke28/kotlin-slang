package com.shivaduke.kotlinslang.sample

import com.shivaduke.kotlinslang.SlangCompiler

/**
 * The one entry point the instrumentation test calls into. It is kept by name in
 * proguard-rules.pro so the minified test APK can reach it, while everything under
 * com.shivaduke.kotlinslang stays fully exposed to R8 like in a real consumer app.
 */
object ShaderCheck {

    /** Compiles [SampleShader] and returns one `name (stage): N bytes` line per entry point. */
    fun compile(): List<String> =
        SlangCompiler().compile(SampleShader.SOURCE).entryPoints.map { entryPoint ->
            "${entryPoint.name} (${entryPoint.stage}): ${entryPoint.spirv.size} bytes"
        }
}
