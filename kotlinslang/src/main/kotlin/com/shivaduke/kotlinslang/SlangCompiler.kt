package com.shivaduke.kotlinslang

/**
 * Compiles a single Slang source to SPIR-V.
 *
 * A convenience over [SlangSession] for sources that stand on their own: each call runs
 * in a fresh session. Use [SlangSession] directly to load several modules that import
 * one another, or to reuse loaded modules across compilations.
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
    fun compile(source: String, macros: Map<String, String> = emptyMap()): CompileResult =
        SlangSession(macros).use { session ->
            session.loadModule(MODULE_NAME, source).compile()
        }

    private companion object {
        const val MODULE_NAME = "shader"
    }
}
