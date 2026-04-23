#!/usr/bin/env bash
# Build a STATIC llama.xcframework (llama + ggml + mtmd) for iOS device + simulator.
#
# Usage:
#   ./scripts/build_llama_ios.sh [path/to/llama.cpp]
#
# Default llama.cpp path: ~/Desktop/llama.cpp
# Output: ios/Frameworks/llama.xcframework
#
# Requirements:
#   - macOS with Xcode installed
#   - cmake >= 3.28  (pip3 install cmake --user)

set -euo pipefail

LLAMA_CPP="${1:-$HOME/Desktop/llama.cpp}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$REPO_ROOT/ios/Frameworks"
BUILD_ROOT="$LLAMA_CPP/build-ican"

if [ ! -d "$LLAMA_CPP" ]; then
    echo "Error: llama.cpp not found at $LLAMA_CPP"
    echo "Usage: $0 [path/to/llama.cpp]"
    exit 1
fi

echo "==> Building static llama.xcframework with mtmd"
echo "    llama.cpp : $LLAMA_CPP"
echo "    output    : $OUTPUT_DIR/llama.xcframework"

# ── Shared cmake flags ─────────────────────────────────────────────────────
CMAKE_COMMON=(
    -G Xcode
    -DLLAMA_BUILD_TOOLS=ON
    -DLLAMA_BUILD_COMMON=ON
    -DLLAMA_BUILD_EXAMPLES=OFF
    -DLLAMA_BUILD_TESTS=OFF
    -DLLAMA_BUILD_SERVER=OFF
    -DGGML_METAL=ON
    -DGGML_METAL_EMBED_LIBRARY=ON
    -DGGML_METAL_USE_BF16=ON
    -DBUILD_SHARED_LIBS=OFF
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY=""
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
)

# ── Libs to merge (pattern: replace {SUFFIX} with sdk suffix) ─────────────
STATIC_LIBS=(
    "src/Release-{SUFFIX}/libllama.a"
    "ggml/src/Release-{SUFFIX}/libggml.a"
    "ggml/src/Release-{SUFFIX}/libggml-base.a"
    "ggml/src/Release-{SUFFIX}/libggml-cpu.a"
    "ggml/src/ggml-metal/Release-{SUFFIX}/libggml-metal.a"
    "ggml/src/ggml-blas/Release-{SUFFIX}/libggml-blas.a"
    "tools/mtmd/Release-{SUFFIX}/libmtmd.a"
    "common/Release-{SUFFIX}/libllama-common.a"
)

build_slice() {
    local name="$1"    # build-ios-device | build-ios-sim
    local sdk="$2"     # iphoneos | iphonesimulator
    local archs="$3"   # space-separated: "arm64" or "arm64 x86_64"
    local suffix="$4"  # iphoneos | iphonesimulator

    local build_dir="$BUILD_ROOT/$name"
    echo ""
    echo "── Configuring $name (sdk=$sdk archs='$archs') ──"

    cmake -B "$build_dir" \
        "${CMAKE_COMMON[@]}" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$sdk" \
        -DCMAKE_OSX_ARCHITECTURES="${archs// /;}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="16.0" \
        "$LLAMA_CPP"

    echo "── Building $name ──"
    cmake --build "$build_dir" --config Release --target mtmd -- -quiet

    # Collect libs that actually exist
    local lib_paths=()
    for pattern in "${STATIC_LIBS[@]}"; do
        local path="$build_dir/${pattern//\{SUFFIX\}/$suffix}"
        if [ -f "$path" ]; then
            lib_paths+=("$path")
        else
            echo "    Warning: $(basename $path) not found, skipping"
        fi
    done

    if [ ${#lib_paths[@]} -eq 0 ]; then
        echo "ERROR: No static libs found for $name"
        exit 1
    fi

    echo "── Merging ${#lib_paths[@]} libs → libllama.a ──"
    xcrun libtool -static -o "$build_dir/libllama.a" "${lib_paths[@]}" 2>/dev/null
    echo "── Slice $name done ──"
}

# ── Build device and simulator slices ─────────────────────────────────────
build_slice "build-ios-device" "iphoneos"        "arm64"        "iphoneos"
build_slice "build-ios-sim"    "iphonesimulator" "arm64 x86_64" "iphonesimulator"

# ── Assemble headers (shared by both slices) ──────────────────────────────
HEADERS_DIR="$BUILD_ROOT/xcfw-headers"
rm -rf "$HEADERS_DIR"
mkdir -p "$HEADERS_DIR"

# Copy all public headers
cp "$LLAMA_CPP/include/"*.h         "$HEADERS_DIR/"
cp "$LLAMA_CPP/ggml/include/"*.h    "$HEADERS_DIR/"
cp "$LLAMA_CPP/tools/mtmd/mtmd.h"         "$HEADERS_DIR/"
cp "$LLAMA_CPP/tools/mtmd/mtmd-helper.h"  "$HEADERS_DIR/"

# CRITICAL: use plain `module`, NOT `framework module`.
# `framework module` requires a .framework directory layout — a static
# xcframework is just a .a + Headers, so Clang can't find the umbrella header
# when the framework keyword is used.
cat > "$HEADERS_DIR/module.modulemap" <<'MODULEMAP'
module llama {
    header "llama.h"
    header "mtmd.h"
    header "mtmd-helper.h"
    export *
}
MODULEMAP

# ── Build xcframework ──────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/llama.xcframework"

echo ""
echo "── Creating llama.xcframework ──"
xcodebuild -create-xcframework \
    -library "$BUILD_ROOT/build-ios-device/libllama.a" \
    -headers "$HEADERS_DIR" \
    -library "$BUILD_ROOT/build-ios-sim/libllama.a" \
    -headers "$HEADERS_DIR" \
    -output "$OUTPUT_DIR/llama.xcframework"

echo ""
echo "==> Done: $OUTPUT_DIR/llama.xcframework"
echo ""
echo "In Xcode:"
echo "  1. Product → Clean Build Folder  (Cmd+Shift+K)"
echo "  2. Confirm llama.xcframework is in Runner target → Do Not Embed"
echo "  3. Cmd+B"
