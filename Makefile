# Slang Android Build Makefile

# Directories
PROJECT_ROOT := $(shell pwd)
SLANG_DIR := $(PROJECT_ROOT)/slang
BUILD_DIR := $(PROJECT_ROOT)/build

# Android configuration
ANDROID_NDK ?= $(HOME)/Library/Android/sdk/ndk/28.2.13676358
ANDROID_PLATFORM ?= android-29
NDK_TOOLCHAIN := $(ANDROID_NDK)/build/cmake/android.toolchain.cmake
# NDK host prebuilt tag (darwin-x86_64 on macOS including Apple Silicon, linux-x86_64 on Linux)
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
HOST_TAG := darwin-x86_64
else
HOST_TAG := linux-x86_64
endif
NDK_BIN := $(ANDROID_NDK)/toolchains/llvm/prebuilt/$(HOST_TAG)/bin

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m # No Color

# Build configuration
CMAKE_BUILD_TYPE := Release
NINJA := ninja

.PHONY: help all generators android-arm64 build verify clean

help:
	@echo "$(GREEN)Slang Android Build System$(NC)"
	@echo ""
	@echo "Available targets:"
	@echo "  $(YELLOW)generators$(NC)    - Build code generators (host)"
	@echo "  $(YELLOW)android-arm64$(NC) - Build for Android (arm64-v8a)"
	@echo "  $(YELLOW)build$(NC)         - Build all ABIs"
	@echo "  $(YELLOW)verify$(NC)        - Verify build artifacts"
	@echo "  $(YELLOW)clean$(NC)         - Clean all build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  ANDROID_NDK=$(ANDROID_NDK)"
	@echo "  ANDROID_PLATFORM=$(ANDROID_PLATFORM)"

all: build

# Build generators (host environment)
generators:
	@echo "$(YELLOW)[1/2] Building generators (host)...$(NC)"
	@if [ -d "$(SLANG_DIR)/generators/bin" ] || [ -d "$(SLANG_DIR)/generators/generators" ]; then \
		echo "Generators already built. Skipping..."; \
	else \
		cd $(SLANG_DIR) && \
		mkdir -p generators && \
		cd generators && \
		cmake .. \
			-G Ninja \
			-DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) \
			-DSLANG_ENABLE_TESTS=OFF \
			-DSLANG_ENABLE_EXAMPLES=OFF \
			-DSLANG_ENABLE_GFX=OFF \
			-DSLANG_ENABLE_SLANG_RHI=OFF && \
		$(NINJA); \
	fi
	@echo "$(GREEN)✓ Generators ready$(NC)"

# Build for Android (arm64-v8a)
android-arm64: generators
	@echo "$(YELLOW)[2/2] Building for Android (arm64-v8a)...$(NC)"
	@cd $(SLANG_DIR) && \
	rm -rf build-android-arm64 && \
	mkdir -p build-android-arm64 && \
	cd build-android-arm64 && \
	cmake .. \
		-G Ninja \
		-DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) \
		-DCMAKE_TOOLCHAIN_FILE=$(NDK_TOOLCHAIN) \
		-DANDROID_ABI=arm64-v8a \
		-DANDROID_PLATFORM=$(ANDROID_PLATFORM) \
		-DSLANG_GENERATORS_PATH=$(SLANG_DIR)/generators/generators/Release/bin \
		-DSLANG_LIB_TYPE=STATIC \
		-DSLANG_ENABLE_TESTS=OFF \
		-DSLANG_ENABLE_EXAMPLES=OFF \
		-DSLANG_ENABLE_GFX=OFF \
		-DSLANG_ENABLE_SLANGD=OFF \
		-DSLANG_ENABLE_SLANGC=OFF \
		-DSLANG_ENABLE_SLANGRT=OFF \
		-DSLANG_ENABLE_SLANGI=OFF && \
	$(NINJA) libslang-compiler.a libcompiler-core.a libcore.a && \
	$(NDK_BIN)/llvm-strip -S Release/lib/libslang-compiler.a && \
	$(NDK_BIN)/llvm-strip -S Release/lib/libcompiler-core.a && \
	$(NDK_BIN)/llvm-strip -S Release/lib/libcore.a && \
	$(NDK_BIN)/llvm-strip -S external/miniz/libminiz.a && \
	$(NDK_BIN)/llvm-strip -S external/lz4/build/cmake/liblz4.a && \
	$(NDK_BIN)/llvm-strip -S external/cmark/src/libcmark-gfm.a
	@mkdir -p $(BUILD_DIR)/android-arm64
	@cp $(SLANG_DIR)/build-android-arm64/Release/lib/*.a $(BUILD_DIR)/android-arm64/
	@cp $(SLANG_DIR)/build-android-arm64/external/miniz/libminiz.a $(BUILD_DIR)/android-arm64/
	@cp $(SLANG_DIR)/build-android-arm64/external/lz4/build/cmake/liblz4.a $(BUILD_DIR)/android-arm64/
	@cp $(SLANG_DIR)/build-android-arm64/external/cmark/src/libcmark-gfm.a $(BUILD_DIR)/android-arm64/
	@echo "$(YELLOW)Merging libraries into single archive...$(NC)"
	@cd $(BUILD_DIR)/android-arm64 && \
	printf 'create libSlangCompiler.a\naddlib libslang-compiler.a\naddlib libcompiler-core.a\naddlib libcore.a\naddlib libminiz.a\naddlib liblz4.a\naddlib libcmark-gfm.a\nsave\nend\n' | $(NDK_BIN)/llvm-ar -M
	@echo "$(GREEN)✓ Android (arm64-v8a) build complete$(NC)"

# Build all ABIs
build: android-arm64
	@echo "$(GREEN)✓ All ABIs built successfully$(NC)"
	@echo ""
	@echo "$(YELLOW)Build artifact sizes:$(NC)"
	@du -h $(BUILD_DIR)/*/*.a | sort

# Verify build artifacts
verify:
	@echo "$(YELLOW)Verifying build artifacts...$(NC)"
	@if [ -f "$(BUILD_DIR)/android-arm64/libSlangCompiler.a" ]; then \
		echo "$(GREEN)✓ Android (arm64-v8a) merged library:$(NC)"; \
		ls -lh $(BUILD_DIR)/android-arm64/libSlangCompiler.a; \
		$(NDK_BIN)/llvm-readelf -h $$($(NDK_BIN)/llvm-ar t $(BUILD_DIR)/android-arm64/libSlangCompiler.a | head -1) 2>/dev/null || true; \
	else \
		echo "$(RED)✗ Android (arm64-v8a) library not found$(NC)"; \
	fi

# Clean all build artifacts
clean:
	@echo "$(YELLOW)Cleaning build artifacts...$(NC)"
	@rm -rf $(SLANG_DIR)/build-android-arm64
	@rm -rf $(SLANG_DIR)/generators
	@rm -rf $(BUILD_DIR)
	@echo "$(GREEN)✓ Clean complete$(NC)"
