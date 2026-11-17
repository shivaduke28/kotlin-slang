package com.shivaduke.kotlinslang

/**
 * `slang::ISession`: a scope for loading modules and compiling them for the targets given
 * in its [SlangSessionDesc].
 *
 * Modules stay loaded in the session, so a module can `import` any module already loaded
 * into it by name, and a module is parsed once no matter how many others import it.
 *
 * The session owns every object obtained from it, directly or indirectly: modules, entry
 * points, composite and linked component types, and all reflection objects. They stay
 * valid until [close] and throw [IllegalStateException] when used afterwards. Native
 * memory grows with everything loaded and linked in the session until it is closed.
 *
 * Not thread-safe; see [SlangGlobalSession].
 */
class SlangSession internal constructor(
    /** `ISession::getGlobalSession`. */
    val globalSession: SlangGlobalSession,
    private var handle: Long,
) : AutoCloseable {

    /**
     * `ISession::loadModule`: loads a module as `import moduleName;` would, from the
     * modules already loaded or from the session's search paths.
     *
     * @param outDiagnostics receives the diagnostics Slang produced, if any
     * @throws SlangCompileException with stage `load` if the module cannot be loaded
     */
    fun loadModule(moduleName: String, outDiagnostics: StringBuilder? = null): SlangModule {
        val diagnostics = arrayOfNulls<String>(1)
        val module = SlangNative.sessionLoadModule(requireOpen(), moduleName, diagnostics)
        return SlangModule(this, checkResult("load", module, diagnostics, outDiagnostics))
    }

    /**
     * `ISession::loadModuleFromSourceString`: loads [string] as the module [moduleName],
     * which modules loaded afterwards can refer to with `import moduleName;`.
     *
     * @param path the file name Slang reports in diagnostics for this source
     * @param outDiagnostics receives the diagnostics Slang produced, if any
     * @throws SlangCompileException with stage `load` if the source does not compile
     */
    fun loadModuleFromSourceString(
        moduleName: String,
        path: String,
        string: String,
        outDiagnostics: StringBuilder? = null,
    ): SlangModule {
        val diagnostics = arrayOfNulls<String>(1)
        val module = SlangNative.sessionLoadModuleFromSourceString(
            requireOpen(), moduleName, path, string, diagnostics,
        )
        return SlangModule(this, checkResult("load", module, diagnostics, outDiagnostics))
    }

    /**
     * `ISession::createCompositeComponentType`: combines modules and entry points into
     * one component type, in the given order.
     *
     * @param outDiagnostics receives the diagnostics Slang produced, if any
     * @throws SlangCompileException with stage `compose` on failure
     */
    fun createCompositeComponentType(
        componentTypes: List<SlangComponentType>,
        outDiagnostics: StringBuilder? = null,
    ): SlangComponentType {
        componentTypes.forEach { require(it.session === this) { "Component type belongs to another session" } }
        val diagnostics = arrayOfNulls<String>(1)
        val composite = SlangNative.sessionCreateCompositeComponentType(
            requireOpen(),
            LongArray(componentTypes.size) { componentTypes[it].handle },
            diagnostics,
        )
        return SlangComponentType(this, checkResult("compose", composite, diagnostics, outDiagnostics))
    }

    /** `ISession::getLoadedModuleCount`. */
    val loadedModuleCount: Long
        get() = SlangNative.sessionGetLoadedModuleCount(requireOpen())

    /** `ISession::getLoadedModule`. */
    fun getLoadedModule(index: Long): SlangModule? =
        SlangNative.sessionGetLoadedModule(requireOpen(), index).takeIf { it != 0L }
            ?.let { SlangModule(this, it) }

    /** Releases the session and everything obtained from it. */
    override fun close() {
        if (handle != 0L) {
            SlangNative.sessionRelease(handle)
            handle = 0L
        }
    }

    internal fun requireOpen(): Long {
        check(handle != 0L) { "SlangSession is closed" }
        return handle
    }

    /**
     * Forwards the diagnostics of a native call to [outDiagnostics] and returns [result],
     * or throws when the call reported failure by returning null.
     */
    internal fun <T> checkResult(
        stage: String,
        result: T?,
        diagnostics: Array<String?>,
        outDiagnostics: StringBuilder?,
    ): T {
        val text = diagnostics[0].orEmpty()
        outDiagnostics?.append(text)
        if (result == null || result == 0L) throw SlangCompileException(stage, text)
        return result
    }
}
