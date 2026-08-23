package com.shivaduke.kotlinslang

import org.json.JSONArray
import org.json.JSONObject

/**
 * Compiles Slang source to SPIR-V.
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
    fun compile(source: String, macros: Map<String, String> = emptyMap()): CompileResult {
        val result = nativeCompile(
            source,
            macros.keys.toTypedArray(),
            macros.values.toTypedArray(),
        ) ?: throw SlangCompileException("jni", "nativeCompile returned null")

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
            diagnostics = json.optString("diagnostics", ""),
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

    private external fun nativeCompile(
        source: String,
        macroKeys: Array<String>,
        macroValues: Array<String>,
    ): NativeCompileResult?

    private inline fun <T> JSONArray.map(transform: (JSONObject) -> T): List<T> =
        (0 until length()).map { transform(getJSONObject(it)) }

    companion object {
        init {
            System.loadLibrary("kotlinslang")
        }
    }
}
