# kotlin-slang

Kotlin/Android bindings for the [Slang](https://shader-slang.org/) shader compiler.

The Android counterpart of [swift-slang](https://github.com/shivaduke28/swift-slang):
builds `libslang` for Android (NDK, arm64-v8a) and exposes an on-device
Slang → SPIR-V compilation API to Kotlin via a thin JNI layer.

> **Status**: work in progress (feasibility spike).

## Architecture

```
libslang (C++, git submodule, static)
   ↑
C++ wrapper: compile + reflection extraction, minimal JNI surface
   ↑
Kotlin API (Android library → AAR)
```

- The `slang/` submodule is **build-time only**. Consumers depend on a
  prebuilt AAR published via GitHub Releases; the submodule never reaches
  the app build, and app size is affected only by the bundled `.so`.
- Slang is pinned to the same version as swift-slang (currently `v2026.4.2`)
  so that reflection behavior stays consistent across platforms.

## Building

Prerequisites: macOS, CMake, Ninja, Android NDK (28.x).

```bash
git submodule update --init --recursive
make build            # host generators + Android arm64-v8a static libs
make verify
```

Variables:

```bash
make build ANDROID_NDK=$HOME/Library/Android/sdk/ndk/28.2.13676358 ANDROID_PLATFORM=android-29
```

Artifacts are placed in `build/android-arm64/libSlangCompiler.a`
(slang-compiler + compiler-core + core + miniz + lz4 merged).

## License

Apache License 2.0 with LLVM exception, same as Slang. See [LICENSE](LICENSE).
