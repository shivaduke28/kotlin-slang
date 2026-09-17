# Everything under com.shivaduke.kotlinslang is deliberately left to R8 so this app
# behaves like a real consumer. Only the test's entry point is kept by name.
-keep class com.shivaduke.kotlinslang.sample.ShaderCheck { *; }

# The instrumentation test APK borrows the Kotlin stdlib from this app (AGP strips
# dependencies the app already ships). Keep it whole so the minified test APK links.
-keep class kotlin.** { *; }
-dontwarn kotlin.**
