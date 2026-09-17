# The test APK is minified too (testBuildType = release). androidx.test references
# errorprone annotations that are compile-only, so silence R8 about them.
-dontwarn com.google.errorprone.annotations.**
