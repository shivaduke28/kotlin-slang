# kotlin-slang

Kotlin/Android bindings for the [Slang](https://shader-slang.org/) shader compiler.

The Android counterpart of [swift-slang](https://github.com/shivaduke28/swift-slang):
builds `libslang` for Android (NDK, arm64-v8a) and exposes on-device
Slang → SPIR-V compilation to Kotlin via a thin JNI layer.

> **Status**: work in progress.

## Architecture

```
libslang (C++, git submodule, static)          slang/ + Makefile
   ↑
JNI wrapper: compile + reflection → JSON       kotlinslang/src/main/cpp/
   ↑
Kotlin API (Android library → AAR)             kotlinslang/src/main/kotlin/
```

- The `slang/` submodule is **build-time only**. Consumers depend on a
  prebuilt AAR; the submodule never reaches the app build, and app size is
  affected only by the bundled `.so` (~11 MB download increment).
- Slang is pinned to the same version as swift-slang (currently `v2026.13.1`)
  so that reflection behavior stays consistent across platforms.
- The JNI surface is a single call returning SPIR-V blobs plus reflection
  metadata (JSON); typed models live in Kotlin.

## Installation

AARs are published as GitHub Release assets. Consume them directly via an
Ivy repository — no authentication, no binary checked into your app repo:

```kotlin
// settings.gradle.kts or build.gradle.kts
repositories {
    ivy {
        url = uri("https://github.com/shivaduke28/kotlin-slang/releases/download")
        patternLayout { artifact("v[revision]/[artifact]-[revision].[ext]") }
        metadataSources { artifact() }
        content { includeGroup("com.shivaduke") }
    }
}

dependencies {
    implementation("com.shivaduke:kotlinslang:0.1.0@aar")
}
```

## Usage

```kotlin
val compiler = SlangCompiler()
val result = compiler.compile(source, macros = mapOf("RESOLUTION_X" to "1920"))

result.entryPoints  // name, stage, SPIR-V bytes per entry point
result.parameters   // name, category, binding index/space, uniform offset,
                    // size/alignment, resource element type, user attributes
```

Compilation failures throw `SlangCompileException` with Slang diagnostics.

Note: the Slang global session is not thread-safe — call `compile` from a
single thread (or serialize externally).

## Building

Prerequisites: macOS, CMake, Ninja, Android NDK 28.x, JDK 17+.

```bash
git submodule update --init --recursive
make build                                  # slang static libs (host generators + arm64-v8a)
./gradlew :kotlinslang:assembleRelease      # AAR
./gradlew :kotlinslang:connectedAndroidTest # instrumented tests (device required)
```

`make build` variables:

```bash
make build ANDROID_NDK=$HOME/Library/Android/sdk/ndk/28.2.13676358 ANDROID_PLATFORM=android-29
```

## Testing

Instrumented tests compile the shader corpus in
`kotlinslang/src/androidTest/assets/shaders` on a real device and assert SPIR-V
output and reflection layout.

`spike/` contains standalone C++ verification tools (smoke/corpus/reflection
dumps) used during the initial feasibility spike; they can be run directly via
adb without the Gradle toolchain.

## Releasing

Trigger the Release workflow (GitHub Actions, `workflow_dispatch`) with a
version number (e.g. `0.1.0`). CI builds the slang static libraries with the
NDK, assembles the AAR, tags `v<version>`, and attaches
`kotlinslang-<version>.aar` to the GitHub Release.

## License

Apache License 2.0 with LLVM exception, same as Slang. See [LICENSE](LICENSE).
