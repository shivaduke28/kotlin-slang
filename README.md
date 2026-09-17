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
    implementation("com.shivaduke:kotlinslang:0.2.0@aar")
}
```

The AAR ships consumer ProGuard rules (`kotlinslang/consumer-rules.pro`), so
no extra keep rules are needed in apps that enable R8/minification.

## Usage

```kotlin
val compiler = SlangCompiler()
val result = compiler.compile(source, macros = mapOf("RESOLUTION_X" to "1920"))

result.entryPoints  // name, stage, SPIR-V bytes and user attributes per entry point
result.parameters   // name, category, binding index/space, uniform offset,
                    // size/alignment, scalar type, resource element type,
                    // user attributes
result.globalConstantBuffer  // binding, descriptor set and byte size of the
                             // implicit constant buffer Slang synthesises for
                             // loose uniform parameters, or null when the
                             // shader declares none
```

User attributes are surfaced as raw name/argument pairs on both parameters and
entry points; interpreting them is the host application's job.

```kotlin
val topology = result.entryPoints.first().attribute("topology")
topology?.intArg(0)
```

### Requirements for Vulkan pipeline creation

- `VkPipelineShaderStageCreateInfo::pName` must be `"main"`. Entry point names
  are normalised to `main` in the emitted SPIR-V; the original function name is
  not preserved. The name reported by reflection selects which entry point's
  SPIR-V to load, and is not a valid `pName`.
- The Vulkan instance must be created with `VkApplicationInfo::apiVersion` of
  1.2 or higher, because the output targets SPIR-V 1.5.

Violating either returns `VK_ERROR_INITIALIZATION_FAILED` from
`vkCreateGraphicsPipelines`, with no further diagnostic unless the validation
layers are enabled.

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

`sample/` is a minimal app that depends on `:kotlinslang` with R8 enabled. Its
instrumented test runs against the minified release build
(`./gradlew :sample:connectedAndroidTest`) and guards the consumer ProGuard
rules shipped in the AAR.

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
