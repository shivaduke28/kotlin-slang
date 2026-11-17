# Shipped inside the AAR (consumerProguardFiles) and applied to every app that depends
# on kotlinslang with R8/ProGuard enabled.

# Native methods are matched by name against the JNI symbols (src/main/cpp/kotlinslang_jni.cpp).
# AGP's default rules already keep them, but not every consumer uses those defaults.
# The JNI layer resolves no classes or members by name, so nothing else needs keeping.
-keepclasseswithmembernames class com.shivaduke.kotlinslang.** { native <methods>; }
