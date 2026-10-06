package com.shivaduke.kotlinslang

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Compile-time benchmark, mirroring swift-slang's CompileBenchmarkTests. Compiles a
 * PBR-style fragment shader (generics, struct uniform, textures) to SPIR-V 30 times and
 * logs the median. Used to track Slang compile performance across version updates.
 *
 * Run with
 *   ./gradlew :kotlinslang:connectedAndroidTest \
 *     -Pandroid.testInstrumentationRunnerArguments.class=com.shivaduke.kotlinslang.CompileBenchmarkTest
 * and read the BENCH line from `adb logcat -s CompileBenchmark`.
 *
 * Each sample covers a full SlangCompiler.compile call (session creation, SPIR-V emission
 * and reflection), unlike swift-slang which excludes session creation. One warm-up compile
 * runs first so the lazily created global session is not counted.
 */
@RunWith(AndroidJUnit4::class)
class CompileBenchmarkTest {

    @Test
    fun compileBenchmark() {
        val source = InstrumentationRegistry.getInstrumentation().context.assets
            .open("bench/pbr.slang").bufferedReader().use { it.readText() }
        val compiler = SlangCompiler()
        val iterations = 30

        compiler.compile(source)

        val samples = (0 until iterations).map {
            val start = System.nanoTime()
            val result = compiler.compile(source)
            val end = System.nanoTime()
            assertTrue(result.entryPoints.single().spirv.isNotEmpty())
            (end - start) / 1_000_000.0
        }

        val sorted = samples.sorted()
        val median = sorted[sorted.size / 2]
        Log.i(
            "CompileBenchmark",
            "BENCH median=%.2fms mean=%.2fms min=%.2fms max=%.2fms n=%d".format(
                median, samples.average(), sorted.first(), sorted.last(), iterations,
            ),
        )
    }
}
