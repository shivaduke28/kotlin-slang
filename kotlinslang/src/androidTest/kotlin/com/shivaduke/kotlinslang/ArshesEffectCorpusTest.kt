package com.shivaduke.kotlinslang

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 実運用サイズのArshesエフェクト（assets/arshes_effects）をSPIR-Vにコンパイルし、
 * 成功率とコンパイル所要時間を計測する。
 *
 * コーパスは arshes-playground リポジトリの `shaders/` 由来。同リポジトリの
 * `connected_shader.slang` は削除済みモジュール（`import foundation`）に依存しており
 * Metalターゲットでも同じ理由で落ちるため、ターゲット差の計測を濁さないよう除外している。
 *
 * 計測結果はタグ [REPORT_TAG] でlogcatに出力する。
 */
@RunWith(AndroidJUnit4::class)
class ArshesEffectCorpusTest {

    private val compiler = SlangCompiler()

    private val macros = mapOf(
        "RESOLUTION_X" to "1920",
        "RESOLUTION_Y" to "1080",
        "DEPTH_RESOLUTION_X" to "256",
        "DEPTH_RESOLUTION_Y" to "192",
    )

    private fun readAsset(path: String): String =
        InstrumentationRegistry.getInstrumentation().context.assets.open(path)
            .bufferedReader().use { it.readText() }

    private data class Measurement(
        val name: String,
        val sourceLines: Int,
        val elapsedMs: Long,
        val entryPoints: Int,
        val spirvBytes: Int,
        val parameters: Int,
        val error: String?,
    )

    @Test
    fun compilesArshesEffectCorpus() {
        val assets = InstrumentationRegistry.getInstrumentation().context.assets
        val prelude = readAsset("RangeAttribute.slang")
        val corpus = assets.list("arshes_effects")!!.sorted()
        assertTrue("corpus is empty", corpus.isNotEmpty())

        // 初回コンパイルはglobal session初期化とcore module読み込みを含むので分けて計測する
        val coldStart = System.nanoTime()
        compiler.compile("$prelude\n[shader(\"fragment\")]\nfloat4 f() : SV_Target { return 1; }", macros)
        val coldMs = (System.nanoTime() - coldStart) / 1_000_000

        val results = corpus.map { name ->
            val source = prelude + "\n" + readAsset("arshes_effects/$name")
            val lines = source.count { it == '\n' } + 1
            val start = System.nanoTime()
            try {
                val result = compiler.compile(source, macros)
                val ms = (System.nanoTime() - start) / 1_000_000
                Measurement(
                    name = name,
                    sourceLines = lines,
                    elapsedMs = ms,
                    entryPoints = result.entryPoints.size,
                    spirvBytes = result.entryPoints.sumOf { it.spirv.size },
                    parameters = result.parameters.size,
                    error = null,
                )
            } catch (e: SlangCompileException) {
                val ms = (System.nanoTime() - start) / 1_000_000
                Measurement(name, lines, ms, 0, 0, 0, "[${e.stage}] ${e.diagnostics}")
            }
        }

        report(coldMs, results)

        val failures = results.filter { it.error != null }
        assertTrue(
            "SPIR-V compile failed for ${failures.size}/${results.size}:\n" +
                failures.joinToString("\n") { "${it.name}: ${it.error}" },
            failures.isEmpty(),
        )
    }

    private fun report(coldMs: Long, results: List<Measurement>) {
        val ok = results.count { it.error == null }
        val warm = results.filter { it.error == null }.map { it.elapsedMs }.sorted()
        Log.i(REPORT_TAG, "--- Arshes effect corpus: SPIR-V compile ---")
        Log.i(REPORT_TAG, String.format("%-26s %6s %7s %4s %8s %5s", "shader", "lines", "ms", "eps", "spirvB", "params"))
        for (r in results) {
            Log.i(
                REPORT_TAG,
                String.format(
                    "%-26s %6d %7d %4d %8d %5d %s",
                    r.name, r.sourceLines, r.elapsedMs, r.entryPoints, r.spirvBytes, r.parameters,
                    r.error ?: "",
                ),
            )
        }
        Log.i(REPORT_TAG, "success: $ok/${results.size}")
        Log.i(REPORT_TAG, "cold first compile: ${coldMs}ms (session init included)")
        if (warm.isNotEmpty()) {
            Log.i(
                REPORT_TAG,
                "warm compile ms: total=${warm.sum()} min=${warm.first()} " +
                    "median=${warm[warm.size / 2]} max=${warm.last()} mean=${warm.sum() / warm.size}",
            )
        }
        for (r in results.filter { it.error != null }) {
            Log.i(REPORT_TAG, "FAIL ${r.name}\n${r.error}")
        }
    }

    private companion object {
        const val REPORT_TAG = "ArshesCorpus"
    }
}
