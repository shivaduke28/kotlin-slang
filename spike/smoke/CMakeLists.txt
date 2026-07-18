cmake_minimum_required(VERSION 3.22)
project(kotlinslang_smoke CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Prebuilt merged slang static library (make build)
set(SLANG_LIB ${CMAKE_CURRENT_SOURCE_DIR}/../../build/android-arm64/libSlangCompiler.a)
set(SLANG_INCLUDE ${CMAKE_CURRENT_SOURCE_DIR}/../../slang/include)

add_library(kotlinslang SHARED smoke.cpp)
target_include_directories(kotlinslang PRIVATE ${SLANG_INCLUDE})
target_compile_definitions(kotlinslang PRIVATE SLANG_STATIC)
target_link_libraries(kotlinslang PRIVATE ${SLANG_LIB} log)
target_link_options(kotlinslang PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL)

# Standalone executable for running the smoke test on-device via adb:
#   adb push smoke_run /data/local/tmp/ && adb shell /data/local/tmp/smoke_run
add_executable(smoke_run main.cpp smoke.cpp)
target_include_directories(smoke_run PRIVATE ${SLANG_INCLUDE})
target_compile_definitions(smoke_run PRIVATE SLANG_STATIC)
target_link_libraries(smoke_run PRIVATE ${SLANG_LIB} log)
target_link_options(smoke_run PRIVATE -Wl,--gc-sections)

# Corpus compile test (Arshes tests/shaders):
#   adb push corpus_run RangeAttribute.slang *.slang /data/local/tmp/
#   adb shell 'cd /data/local/tmp && ./corpus_run RangeAttribute.slang <shaders...>'
add_executable(corpus_run corpus.cpp)
target_include_directories(corpus_run PRIVATE ${SLANG_INCLUDE})
target_compile_definitions(corpus_run PRIVATE SLANG_STATIC)
target_link_libraries(corpus_run PRIVATE ${SLANG_LIB} log)
target_link_options(corpus_run PRIVATE -Wl,--gc-sections)

# Reflection dump (extractParameters equivalent on the SPIR-V target)
add_executable(reflect_run reflect.cpp)
target_include_directories(reflect_run PRIVATE ${SLANG_INCLUDE})
target_compile_definitions(reflect_run PRIVATE SLANG_STATIC)
target_link_libraries(reflect_run PRIVATE ${SLANG_LIB} log)
target_link_options(reflect_run PRIVATE -Wl,--gc-sections)
