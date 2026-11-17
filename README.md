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
JNI wrapper: one function per Slang method     kotlinslang/src/main/cpp/
   ↑
Kotlin API (Android library → AAR)             kotlinslang/src/main/kotlin/
```

- The `slang/` submodule is **build-time only**. Consumers depend on a
  prebuilt AAR; the submodule never reaches the app build, and app size is
  affected only by the bundled `.so` (~11 MB download increment).
- Slang is pinned to the same version as swift-slang (currently `v2026.22`)
  so that reflection behavior stays consistent across platforms.
- The JNI layer forwards each function to one method of the Slang C++ API. The
  Kotlin classes mirror the Slang interfaces on top of it.

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
    implementation("com.shivaduke:kotlinslang:<version>@aar")
}
```

Replace `<version>` with a version from the
[Releases](https://github.com/shivaduke28/kotlin-slang/releases) page, without
the `v` prefix (tag `vX.Y.Z` → `X.Y.Z`).

The AAR ships consumer ProGuard rules (`kotlinslang/consumer-rules.pro`), so
no extra keep rules are needed in apps that enable R8/minification.

## Usage

The API mirrors Slang's own (`slang.h`): the same objects, the same method
names and argument order, with a `Slang` prefix. Slang's documentation applies
as is.

| Slang | kotlin-slang |
| --- | --- |
| `slang::createGlobalSession` | `SlangGlobalSession.create()` |
| `IGlobalSession` | `SlangGlobalSession` |
| `SessionDesc`, `TargetDesc` | `SlangSessionDesc`, `SlangTargetDesc` |
| `ISession` | `SlangSession` |
| `IComponentType` | `SlangComponentType` |
| `IModule`, `IEntryPoint` | `SlangModule`, `SlangEntryPoint` |
| `ProgramLayout`, `EntryPointReflection` | `SlangProgramLayout`, `SlangEntryPointReflection` |
| `VariableLayoutReflection`, `TypeLayoutReflection` | `SlangVariableLayoutReflection`, `SlangTypeLayoutReflection` |
| `VariableReflection`, `TypeReflection`, `FunctionReflection` | `SlangVariableReflection`, `SlangTypeReflection`, `SlangFunctionReflection` |
| `Attribute` | `SlangAttribute` |

```kotlin
val global = SlangGlobalSession.create()   // expensive: create once and reuse
val desc = SlangSessionDesc(
    targets = listOf(SlangTargetDesc(SlangCompileTarget.Spirv, global.findProfile("spirv_1_5"))),
    preprocessorMacros = mapOf("RESOLUTION_X" to "1920"),
)

global.createSession(desc).use { session ->
    // Modules stay loaded in the session and can be imported by name.
    session.loadModuleFromSourceString("common", "common.slang", commonSource)
    val module = session.loadModuleFromSourceString("main", "main.slang", "import common;\n...")

    val entryPoint = module.findEntryPointByName("fragmentMain")!!
    val linked = session.createCompositeComponentType(listOf(module, entryPoint)).link()

    val spirv = linked.getEntryPointCode(entryPointIndex = 0, targetIndex = 0)

    val layout = linked.getLayout()
    val param = layout.getParameterByIndex(0)!!
    param.name
    param.bindingIndex
    param.typeLayout?.getSize()
    param.variable?.getUserAttributeByIndex(0)?.getArgumentValueFloat(0)
}
```

Where Kotlin conventions differ from C++:

- Getters without arguments are properties (`getName()` → `name`).
- Methods that report failure through a null or failed result throw
  `SlangCompileException` carrying the diagnostics. `outDiagnostics` parameters
  take an optional `StringBuilder` that receives the diagnostics, including
  warnings on success.
- Lookups that may legitimately find nothing return null.
- A session owns everything obtained from it — modules, entry points, linked
  programs and reflection objects — and releases it all in `close()`. Only
  `SlangGlobalSession` and `SlangSession` need closing; anything used after its
  session is closed throws `IllegalStateException`.

Not every method of the Slang API is exposed yet; the ones that are behave as
upstream.

### Compiling a single source

`SlangCompiler` is a convenience on top of the classes above: it compiles one
self-contained source to SPIR-V 1.5 with all of its entry points and collects
commonly needed reflection data into plain data classes.

```kotlin
val compiler = SlangCompiler()
val result = compiler.compile(source, macros = mapOf("RESOLUTION_X" to "1920"))

result.entryPoints  // name, stage, SPIR-V bytes and user attributes per entry point
result.parameters   // name, category, binding index/space, uniform offset,
                    // size/alignment, element size/stride, scalar type,
                    // resource element type,
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

Note: a Slang global session and the objects created from it are not
thread-safe — use them, and `SlangCompiler`, from a single thread (or serialize
externally).

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
