# Shipped inside the AAR (consumerProguardFiles) and applied to every app that depends
# on kotlinslang with R8/ProGuard enabled.

# Resolved by name from JNI (FindClass / GetMethodID in src/main/cpp/kotlinslang_jni.cpp).
# R8 cannot see those references, so without this rule the class and its constructor get
# shrunk or renamed and nativeCompile fails with NoSuchMethodError.
-keep class com.shivaduke.kotlinslang.NativeCompileResult { <init>(java.lang.String, byte[][]); }

# Native methods are matched by name against the JNI symbols. AGP's default rules already
# keep them, but not every consumer uses those defaults.
-keepclasseswithmembernames class com.shivaduke.kotlinslang.** { native <methods>; }
