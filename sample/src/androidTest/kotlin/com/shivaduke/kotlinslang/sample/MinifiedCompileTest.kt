package com.shivaduke.kotlinslang.sample

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs against the minified release build (see `testBuildType` in build.gradle.kts) to make
 * sure R8 keeps everything the JNI layer resolves by name.
 */
@RunWith(AndroidJUnit4::class)
class MinifiedCompileTest {

    @Test
    fun compilesUnderR8() {
        val lines = ShaderCheck.compile()

        assertEquals(2, lines.size)
        assertTrue(lines[0], lines[0].startsWith("vertexMain (Vertex): "))
        assertTrue(lines[1], lines[1].startsWith("fragmentMain (Fragment): "))
        lines.forEach { line -> assertTrue(line, !line.endsWith(" 0 bytes")) }
    }
}
