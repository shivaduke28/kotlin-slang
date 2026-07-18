package com.shivaduke.kotlinslang

import org.json.JSONArray
import org.json.JSONObject

/**
 * SlangソースをSPIR-Vにコンパイルする。
 *
 * Slangのglobal sessionはスレッドセーフではないため、このクラスの利用は
 * 単一スレッド（またはアプリ側での直列化）を前提とする。
 */
class SlangCompiler {

    /**
     * [source]をコンパイルし、全エントリポイントのSPIR-Vとリフレクション情報を返す。
     *
     * @throws SlangCompileException コンパイル失敗時（診断メッセージ付き）
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
                resourceResult = p.optJSONObject("resourceResult")?.let { r ->
                    ResourceResultType(
                        kind = TypeKind.from(r.getString("kind")),
                        components = r.getInt("components"),
                        scalar = r.getString("scalar"),
                    )
                },
                attributes = p.getJSONArray("attributes").map { a ->
                    UserAttribute(
                        name = a.getString("name"),
                        args = a.getJSONArray("args").let { args ->
                            (0 until args.length()).map { args.get(it) }
                        },
                    )
                },
            )
        }

        return CompileResult(
            entryPoints = entryPoints,
            parameters = parameters,
            diagnostics = json.optString("diagnostics", ""),
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
