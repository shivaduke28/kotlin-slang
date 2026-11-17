package com.shivaduke.kotlinslang

/**
 * `slang::IComponentType`: a unit of code that can be composed, linked and compiled, such
 * as a module, an entry point, or a composite of them.
 *
 * Owned by its [session]; see [SlangSession] for lifetime.
 */
open class SlangComponentType internal constructor(
    /** `IComponentType::getSession`. */
    val session: SlangSession,
    internal val handle: Long,
) {

    /**
     * `IComponentType::getLayout`: reflection for this program on the target at
     * [targetIndex].
     *
     * @param outDiagnostics receives the diagnostics Slang produced, if any
     * @throws SlangCompileException with stage `layout` if no layout is available
     */
    fun getLayout(targetIndex: Long = 0, outDiagnostics: StringBuilder? = null): SlangProgramLayout {
        session.requireOpen()
        val diagnostics = arrayOfNulls<String>(1)
        val layout = SlangNative.componentTypeGetLayout(handle, targetIndex, diagnostics)
        return SlangProgramLayout(session, session.checkResult("layout", layout, diagnostics, outDiagnostics))
    }

    /**
     * `IComponentType::getEntryPointCode`: the compiled code of the entry point at
     * [entryPointIndex] for the target at [targetIndex]. Requires a linked component type.
     *
     * @param outDiagnostics receives the diagnostics Slang produced, if any
     * @throws SlangCompileException with stage `emit` on failure
     */
    fun getEntryPointCode(
        entryPointIndex: Long,
        targetIndex: Long,
        outDiagnostics: StringBuilder? = null,
    ): ByteArray {
        session.requireOpen()
        val diagnostics = arrayOfNulls<String>(1)
        val code = SlangNative.componentTypeGetEntryPointCode(handle, entryPointIndex, targetIndex, diagnostics)
        return session.checkResult("emit", code, diagnostics, outDiagnostics)
    }

    /**
     * `IComponentType::getTargetCode`: the compiled code of the whole program for the
     * target at [targetIndex]. Requires a linked component type.
     *
     * @param outDiagnostics receives the diagnostics Slang produced, if any
     * @throws SlangCompileException with stage `emit` on failure
     */
    fun getTargetCode(targetIndex: Long, outDiagnostics: StringBuilder? = null): ByteArray {
        session.requireOpen()
        val diagnostics = arrayOfNulls<String>(1)
        val code = SlangNative.componentTypeGetTargetCode(handle, targetIndex, diagnostics)
        return session.checkResult("emit", code, diagnostics, outDiagnostics)
    }

    /**
     * `IComponentType::link`: resolves this component type's dependencies, pulling in the
     * modules it imports, and returns the fully linked program.
     *
     * @param outDiagnostics receives the diagnostics Slang produced, if any
     * @throws SlangCompileException with stage `link` on failure
     */
    fun link(outDiagnostics: StringBuilder? = null): SlangComponentType {
        val diagnostics = arrayOfNulls<String>(1)
        val linked = SlangNative.componentTypeLink(session.requireOpen(), handle, diagnostics)
        return SlangComponentType(session, session.checkResult("link", linked, diagnostics, outDiagnostics))
    }
}

/** `slang::IModule`: a module loaded into a session. */
class SlangModule internal constructor(session: SlangSession, handle: Long) :
    SlangComponentType(session, handle) {

    /**
     * `IModule::findEntryPointByName`. Only finds functions marked as entry points with
     * `[shader("...")]`; use [findAndCheckEntryPoint] for other functions. Returns null if
     * there is no such entry point.
     */
    fun findEntryPointByName(name: String): SlangEntryPoint? =
        SlangNative.moduleFindEntryPointByName(session.requireOpen(), handle, name)
            .takeIf { it != 0L }?.let { SlangEntryPoint(session, it) }

    /**
     * `IModule::getDefinedEntryPointCount`: the number of entry points the module defines.
     * They are not part of the module as a component type; add them when composing.
     */
    val definedEntryPointCount: Int
        get() {
            session.requireOpen()
            return SlangNative.moduleGetDefinedEntryPointCount(handle)
        }

    /** `IModule::getDefinedEntryPoint`. Returns null if [index] cannot be resolved. */
    fun getDefinedEntryPoint(index: Int): SlangEntryPoint? =
        SlangNative.moduleGetDefinedEntryPoint(session.requireOpen(), handle, index)
            .takeIf { it != 0L }?.let { SlangEntryPoint(session, it) }

    /** `IModule::getName`. */
    val name: String
        get() {
            session.requireOpen()
            return SlangNative.moduleGetName(handle).orEmpty()
        }

    /** `IModule::getFilePath`. */
    val filePath: String?
        get() {
            session.requireOpen()
            return SlangNative.moduleGetFilePath(handle)
        }

    /**
     * `IModule::findAndCheckEntryPoint`: finds the function [name] and validates it as an
     * entry point for [stage], even if it has no `[shader("...")]` attribute.
     *
     * @param outDiagnostics receives the diagnostics Slang produced, if any
     * @throws SlangCompileException with stage `entryPoint` if it is not a valid entry point
     */
    fun findAndCheckEntryPoint(
        name: String,
        stage: SlangStage,
        outDiagnostics: StringBuilder? = null,
    ): SlangEntryPoint {
        val diagnostics = arrayOfNulls<String>(1)
        val entryPoint = SlangNative.moduleFindAndCheckEntryPoint(
            session.requireOpen(), handle, name, stage.raw, diagnostics,
        )
        return SlangEntryPoint(session, session.checkResult("entryPoint", entryPoint, diagnostics, outDiagnostics))
    }
}

/** `slang::IEntryPoint`: an entry point function of a module. */
class SlangEntryPoint internal constructor(session: SlangSession, handle: Long) :
    SlangComponentType(session, handle) {

    /** `IEntryPoint::getFunctionReflection`. */
    val functionReflection: SlangFunctionReflection?
        get() {
            session.requireOpen()
            return SlangNative.entryPointGetFunctionReflection(handle)
                .takeIf { it != 0L }?.let { SlangFunctionReflection(session, it) }
        }
}
