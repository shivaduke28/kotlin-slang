package com.shivaduke.kotlinslang

import org.json.JSONArray
import org.json.JSONObject

/**
 * A Slang compilation session: a set of preprocessor macros plus the modules loaded so
 * far. Counterpart of `slang::ISession`, targeting SPIR-V.
 *
 * Modules loaded into a session stay loaded, so a module can `import` any module loaded
 * before it by name, and a shared module is parsed once no matter how many other modules
 * import it.
 *
 * ```
 * SlangSession(macros).use { session ->
 *     session.loadModule("common", commonSource)
 *     val result = session.loadModule("main", "import common; ...").compile()
 * }
 * ```
 *
 * A session holds native memory that grows with every module loaded; [close] it when
 * done. Slang's global session is not thread-safe, so sessions and their modules must be
 * used from a single thread, or calls must be serialized by the application.
 *
 * @param macros preprocessor macros defined for every module loaded into the session
 * @throws SlangCompileException if the native session cannot be created
 */
class SlangSession(macros: Map<String, String> = emptyMap()) : AutoCloseable {

    private var handle: Long =
        nativeCreate(macros.keys.toTypedArray(), macros.values.toTypedArray())

    init {
        if (handle == 0L) throw SlangCompileException("session", "")
    }

    /**
     * Loads [source] into the session as the module [name], which other modules can then
     * refer to with `import name;`. Counterpart of `ISession::loadModuleFromSourceString`.
     *
     * [path] is the file name Slang reports in diagnostics for this source.
     *
     * @throws SlangCompileException with stage `load` if the source does not compile,
     * carrying Slang diagnostics
     * @throws IllegalStateException if the session is closed
     */
    fun loadModule(name: String, source: String, path: String = "$name.slang"): SlangModule {
        val outModule = LongArray(1)
        val diagnostics = nativeLoadModule(requireOpen(), name, path, source, outModule)
        if (outModule[0] == 0L) throw SlangCompileException("load", diagnostics)
        return SlangModule(this, outModule[0], name, diagnostics)
    }

    /** Releases the native session. Modules loaded from it can no longer be compiled. */
    override fun close() {
        if (handle != 0L) {
            nativeDestroy(handle)
            handle = 0L
        }
    }

    internal fun compile(module: SlangModule): CompileResult {
        val result = nativeCompile(requireOpen(), module.handle)
            ?: throw SlangCompileException("jni", "nativeCompile returned null")
        return parseResult(result, module.diagnostics)
    }

    private fun requireOpen(): Long {
        check(handle != 0L) { "SlangSession is closed" }
        return handle
    }

    private fun parseResult(result: NativeCompileResult, diagnostics: String): CompileResult {
        val json = JSONObject(result.json)
        if (!json.getBoolean("ok")) {
            throw SlangCompileException(
                json.optString("errorStage", "unknown"),
                json.optString("diagnostics", ""),
            )
        }

        val entryPoints = json.getJSONArray("entryPoints").map { ep ->
            EntryPoint(
                name = ep.getString("name"),
                stage = ShaderStage.from(ep.getInt("stage")),
                spirv = result.spirv[ep.getInt("spirvIndex")],
                attributes = parseAttributes(ep.getJSONArray("attributes")),
            )
        }

        val parameters = json.getJSONArray("parameters").map { p ->
            ShaderParameter(
                name = p.getString("name"),
                category = ParameterCategory.from(p.getString("category")),
                bindingIndex = p.getInt("bindingIndex"),
                bindingSpace = p.getInt("bindingSpace"),
                uniformOffset = p.getInt("uniformOffset"),
                kind = TypeKind.from(p.optString("kind", "other")),
                size = p.optInt("size", 0),
                alignment = p.optInt("alignment", 0),
                elementSize = p.optInt("elementSize", 0),
                elementStride = p.optInt("elementStride", 0),
                scalar = ScalarType.from(p.optString("scalar", "none")),
                resourceResult = p.optJSONObject("resourceResult")?.let { r ->
                    ResourceResultType(
                        kind = TypeKind.from(r.getString("kind")),
                        components = r.getInt("components"),
                        scalar = ScalarType.from(r.getString("scalar")),
                    )
                },
                attributes = parseAttributes(p.getJSONArray("attributes")),
            )
        }

        val globalCb = json.optJSONObject("globalConstantBuffer")?.let { cb ->
            GlobalConstantBuffer(
                binding = cb.getInt("binding"),
                space = cb.getInt("space"),
                size = cb.getInt("size"),
            )
        }

        return CompileResult(
            entryPoints = entryPoints,
            parameters = parameters,
            globalConstantBuffer = globalCb,
            diagnostics = diagnostics,
        )
    }

    private fun parseAttributes(array: JSONArray): List<UserAttribute> = array.map { a ->
        UserAttribute(
            name = a.getString("name"),
            args = a.getJSONArray("args").let { args ->
                (0 until args.length()).map { args.get(it) }
            },
        )
    }

    private inline fun <T> JSONArray.map(transform: (JSONObject) -> T): List<T> =
        (0 until length()).map { transform(getJSONObject(it)) }

    private external fun nativeCreate(
        macroKeys: Array<String>,
        macroValues: Array<String>,
    ): Long

    private external fun nativeDestroy(session: Long)

    private external fun nativeLoadModule(
        session: Long,
        name: String,
        path: String,
        source: String,
        outModule: LongArray,
    ): String

    private external fun nativeCompile(session: Long, module: Long): NativeCompileResult?

    companion object {
        init {
            System.loadLibrary("kotlinslang")
        }
    }
}

/**
 * A module loaded into a [SlangSession]. Counterpart of `slang::IModule`. It is valid
 * until its session is closed.
 */
class SlangModule internal constructor(
    private val session: SlangSession,
    internal val handle: Long,
    /** The name the module was loaded under, as used by `import`. */
    val name: String,
    /** Diagnostics Slang produced while loading the module; warnings only. */
    val diagnostics: String,
) {

    /**
     * Links the module with every entry point it defines and returns the SPIR-V for each
     * along with the reflection data of the linked program.
     *
     * Modules it imports, directly or transitively, are linked in: uniforms and resources
     * they declare are part of the program and appear in [CompileResult.parameters].
     * Entry points defined in imported modules are not compiled.
     *
     * @throws SlangCompileException on failure, carrying Slang diagnostics
     * @throws IllegalStateException if the session is closed
     */
    fun compile(): CompileResult = session.compile(this)
}
