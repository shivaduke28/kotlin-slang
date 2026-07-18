cmake_minimum_required(VERSION 3.22)
project(kotlinslang CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Prebuilt merged slang static library. Build it first at the repo root:
#   make build
set(REPO_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../..)
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(SLANG_ABI_DIR android-arm64)
else()
    message(FATAL_ERROR "Unsupported ABI: ${ANDROID_ABI}")
endif()
set(SLANG_LIB ${REPO_ROOT}/build/${SLANG_ABI_DIR}/libSlangCompiler.a)
set(SLANG_INCLUDE ${REPO_ROOT}/slang/include)

if(NOT EXISTS ${SLANG_LIB})
    message(FATAL_ERROR "Prebuilt slang library not found: ${SLANG_LIB}. Run 'make build' at the repository root first.")
endif()

add_library(kotlinslang SHARED kotlinslang_jni.cpp)
target_include_directories(kotlinslang PRIVATE ${SLANG_INCLUDE})
target_compile_definitions(kotlinslang PRIVATE SLANG_STATIC)
target_link_libraries(kotlinslang PRIVATE ${SLANG_LIB} log)
target_link_options(kotlinslang PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL)
