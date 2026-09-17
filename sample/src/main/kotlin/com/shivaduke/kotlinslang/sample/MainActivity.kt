package com.shivaduke.kotlinslang.sample

import android.app.Activity
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView

/**
 * Compiles [SampleShader] on launch and prints the result. Exists mainly so that the
 * minified release build has something to run.
 */
class MainActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val text = TextView(this).apply {
            val padding = (16 * resources.displayMetrics.density).toInt()
            setPadding(padding, padding, padding, padding)
        }
        setContentView(ScrollView(this).apply { addView(text) })

        text.text = runCatching { ShaderCheck.compile().joinToString("\n") }
            .getOrElse { error -> "compile failed: $error" }
    }
}
