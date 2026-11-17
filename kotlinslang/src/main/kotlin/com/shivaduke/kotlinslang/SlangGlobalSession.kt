package com.shivaduke.kotlinslang

/**
 * `slang::IGlobalSession`: the top-level object of the Slang compiler, from which
 * sessions are created.
 *
 * Creating one loads the Slang core module and is expensive, so create one and reuse it
 * for every [SlangSession]. A global session and the objects created from it are not
 * thread-safe; use them from a single thread, or serialize access externally.
 *
 * [close] releases the global session. Sessions created from it keep it alive natively,
 * so closing it while sessions are still open is safe, but it can then no longer create
 * new ones.
 */
class SlangGlobalSession private constructor(private var handle: Long) : AutoCloseable {

    /**
     * `IGlobalSession::createSession`.
     *
     * @throws SlangCompileException with stage `session` if the session cannot be created
     */
    fun createSession(desc: SlangSessionDesc): SlangSession {
        val session = SlangNative.globalSessionCreateSession(
            requireOpen(),
            IntArray(desc.targets.size) { desc.targets[it].format.raw },
            IntArray(desc.targets.size) { desc.targets[it].profile },
            desc.searchPaths.toTypedArray(),
            desc.preprocessorMacros.keys.toTypedArray(),
            desc.preprocessorMacros.values.toTypedArray(),
        )
        if (session == 0L) throw SlangCompileException("session", "")
        return SlangSession(this, session)
    }

    /**
     * `IGlobalSession::findProfile`: looks up the ID of a profile such as `spirv_1_5` by
     * name, for use as [SlangTargetDesc.profile]. Returns [SLANG_PROFILE_UNKNOWN] if there
     * is no such profile.
     */
    fun findProfile(name: String): Int = SlangNative.globalSessionFindProfile(requireOpen(), name)

    /** `IGlobalSession::getBuildTagString`: the version of the Slang library. */
    val buildTagString: String
        get() = SlangNative.globalSessionGetBuildTagString(requireOpen()).orEmpty()

    override fun close() {
        if (handle != 0L) {
            SlangNative.globalSessionRelease(handle)
            handle = 0L
        }
    }

    private fun requireOpen(): Long {
        check(handle != 0L) { "SlangGlobalSession is closed" }
        return handle
    }

    companion object {
        /** `SLANG_PROFILE_UNKNOWN`. */
        const val SLANG_PROFILE_UNKNOWN: Int = 0

        /**
         * `slang::createGlobalSession`.
         *
         * @throws SlangCompileException with stage `globalSession` on failure
         */
        fun create(): SlangGlobalSession {
            val handle = SlangNative.createGlobalSession()
            if (handle == 0L) throw SlangCompileException("globalSession", "")
            return SlangGlobalSession(handle)
        }
    }
}

/** `slang::TargetDesc`: a code generation target. */
data class SlangTargetDesc(
    val format: SlangCompileTarget = SlangCompileTarget.Unknown,
    /** A profile ID from [SlangGlobalSession.findProfile]. */
    val profile: Int = SlangGlobalSession.SLANG_PROFILE_UNKNOWN,
)

/** `slang::SessionDesc`: the settings a [SlangSession] is created with. */
data class SlangSessionDesc(
    /** Code generation targets; `targetIndex` arguments index into this list. */
    val targets: List<SlangTargetDesc> = emptyList(),
    /** Directories searched for `#include` and for `import` of modules not yet loaded. */
    val searchPaths: List<String> = emptyList(),
    /** Preprocessor macros (name to value) defined for every module loaded in the session. */
    val preprocessorMacros: Map<String, String> = emptyMap(),
)
