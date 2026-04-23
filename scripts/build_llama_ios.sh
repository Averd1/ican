#!/usr/bin/env bash
# Build llama.xcframework (llama + ggml + mtmd) for iOS device and simulator.
#
# Usage:
#   ./scripts/build_llama_ios.sh [path/to/llama.cpp]
#
# Default llama.cpp path: ~/Desktop/llama.cpp
# Output: ios/Frameworks/llama.xcframework
#
# Requirements:
#   - macOS with Xcode installed
#   - cmake >= 3.28 (brew install cmake)
#
# The standard build-xcframework.sh sets LLAMA_BUILD_TOOLS=OFF which skips
# tools/mtmd entirely. This script enables TOOLS so libmtmd.a is produced,
# then merges it into the xcframework alongside libllama + libggml.

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

echo "==> Building llama.xcframework with mtmd support"
echo "    llama.cpp: $LLAMA_CPP"
echo "    output:    $OUTPUT_DIR/llama.xcframework"

# ── Shared cmake args ──────────────────────────────────────────────────────
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
)

# ── Static libs to merge (relative to build dir / Release-*) ──────────────
# common is needed by mtmd internally
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
    local name="$1"         # e.g. "build-ios-device"
    local sdk="$2"          # e.g. "iphoneos"
    local arch="$3"         # e.g. "arm64" or "arm64;x86_64"
    local suffix="$4"       # e.g. "iphoneos" or "iphonesimulator"
    local min_ver="16.0"

    local build_dir="$BUILD_ROOT/$name"
    echo ""
    echo "── Configuring $name (sdk=$sdk arch=$arch) ──"

    cmake -B "$build_dir" \
        "${CMAKE_COMMON[@]}" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$sdk" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$min_ver" \
        "$LLAMA_CPP"

    echo "── Building $name ──"
    cmake --build "$build_dir" --config Release -- -quiet

    # Merge static libs into one combined.a
    local tmp="$build_dir/combined_tmp"
    mkdir -p "$tmp"

    local lib_paths=()
    for pattern in "${STATIC_LIBS[@]}"; do
        local path="$build_dir/${pattern//\{SUFFIX\}/$suffix}"
        if [ -f "$path" ]; then
            lib_paths+=("$path")
        else
            echo "    Warning: $path not found, skipping"
        fi
    done

    echo "── Merging ${#lib_paths[@]} static libs → combined.a ──"
    xcrun libtool -static -o "$tmp/combined.a" "${lib_paths[@]}" 2>/dev/null

    # Build dynamic framework from combined.a
    local fw_dir="$build_dir/framework/llama.framework"
    mkdir -p "$fw_dir/Headers" "$fw_dir/Modules"

    # Determine install name and link flags
    local install_name="@rpath/llama.framework/llama"

    xcrun -sdk "$sdk" clang++ -dynamiclib \
        -arch "$arch" \
        -miphoneos-version-min="$min_ver" \
        -install_name "$install_name" \
        -framework Foundation \
        -framework Metal \
        -framework Accelerate \
        -framework MetalKit \
        -force_load "$tmp/combined.a" \
        -o "$fw_dir/llama"

    # Copy public headers
    cp "$LLAMA_CPP/include/llama.h"               "$fw_dir/Headers/"
    cp "$LLAMA_CPP/ggml/include/ggml.h"           "$fw_dir/Headers/"
    cp "$LLAMA_CPP/tools/mtmd/mtmd.h"             "$fw_dir/Headers/"
    cp "$LLAMA_CPP/tools/mtmd/mtmd-helper.h"      "$fw_dir/Headers/"

    # module.modulemap (lets Xcode find headers without a bridging header)
    cat > "$fw_dir/Modules/module.modulemap" <<'MODULEMAP'
framework module llama {
    header "llama.h"
    header "ggml.h"
    header "mtmd.h"
    header "mtmd-helper.h"
    export *
}
MODULEMAP

    # Minimal Info.plist
    cat > "$fw_dir/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ggerganov.llama</string>
    <key>CFBundleName</key>
    <string>llama</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>16.0</string>
</dict>
</plist>
PLIST

    echo "── Slice $name done: $fw_dir ──"
}

# ── Build both slices ──────────────────────────────────────────────────────
build_slice "build-ios-device"    "iphoneos"        "arm64"          "iphoneos"
build_slice "build-ios-sim"       "iphonesimulator" "arm64;x86_64"   "iphonesimulator"

# ── Combine into xcframework ───────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

if [ -d "$OUTPUT_DIR/llama.xcframework" ]; then
    echo ""
    echo "── Removing old llama.xcframework ──"
    rm -rf "$OUTPUT_DIR/llama.xcframework"
fi

echo ""
echo "── Creating llama.xcframework ──"
xcodebuild -create-xcframework \
    -framework "$BUILD_ROOT/build-ios-device/framework/llama.framework" \
    -framework "$BUILD_ROOT/build-ios-sim/framework/llama.framework" \
    -output "$OUTPUT_DIR/llama.xcframework"

echo ""
echo "==> Done: $OUTPUT_DIR/llama.xcframework"
echo ""
echo "Next steps:"
echo "  1. Open ios/Runner.xcworkspace in Xcode"
echo "  2. Runner target → General → Frameworks → + → Add Files"
echo "     → select ios/Frameworks/llama.xcframework"
echo "     → Embed: Do Not Embed"
echo "  3. Build Settings → Other Linker Flags → add -ObjC (if not present)"
echo "  4. Cmd+B to build"
