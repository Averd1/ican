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

echo "==> Building llama.xcframework with mtmd support"
echo "    llama.cpp: $LLAMA_CPP"
echo "    output:    $OUTPUT_DIR/llama.xcframework"

# ── Shared cmake args ──────────────────────────────────────────────────────
# LLAMA_BUILD_TOOLS=ON is required so tools/mtmd gets added to the Xcode project.
# Code-signing is disabled so CLI tool targets (which lack bundle IDs) don't fail.
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

# ── Static libs to merge ───────────────────────────────────────────────────
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
    local name="$1"      # e.g. "build-ios-device"
    local sdk="$2"       # e.g. "iphoneos"
    local archs="$3"     # space-separated, e.g. "arm64" or "arm64 x86_64"
    local suffix="$4"    # e.g. "iphoneos" or "iphonesimulator"
    local is_sim="$5"    # "true" or "false"
    local min_ver="16.0"

    local build_dir="$BUILD_ROOT/$name"
    echo ""
    echo "── Configuring $name (sdk=$sdk archs=$archs) ──"

    # cmake expects semicolon-separated architectures
    local cmake_archs="${archs// /;}"

    cmake -B "$build_dir" \
        "${CMAKE_COMMON[@]}" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$sdk" \
        -DCMAKE_OSX_ARCHITECTURES="$cmake_archs" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$min_ver" \
        "$LLAMA_CPP"

    echo "── Building $name (mtmd target only) ──"
    cmake --build "$build_dir" --config Release --target mtmd -- -quiet

    # ── Merge static libs into combined.a ─────────────────────────────────
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

    # ── Build dynamic framework from combined.a ────────────────────────────
    local fw_dir="$build_dir/framework/llama.framework"
    mkdir -p "$fw_dir/Headers" "$fw_dir/Modules"

    local install_name="@rpath/llama.framework/llama"

    # Build -arch flags (one per arch)
    local arch_flags=()
    for a in $archs; do
        arch_flags+=(-arch "$a")
    done

    # Simulator needs -target instead of -miphoneos-version-min
    local platform_flag
    if [ "$is_sim" = "true" ]; then
        platform_flag="-target arm64-apple-ios${min_ver}-simulator"
    else
        platform_flag="-miphoneos-version-min=$min_ver"
    fi

    xcrun -sdk "$sdk" clang++ -dynamiclib \
        "${arch_flags[@]}" \
        $platform_flag \
        -install_name "$install_name" \
        -framework Foundation \
        -framework Metal \
        -framework Accelerate \
        -framework MetalKit \
        -force_load "$tmp/combined.a" \
        -o "$fw_dir/llama"

    # ── Copy public headers ────────────────────────────────────────────────
    # Copy all ggml headers (llama.h transitively includes ggml-cpu.h etc.)
    cp "$LLAMA_CPP/include/llama.h"           "$fw_dir/Headers/"
    cp "$LLAMA_CPP/ggml/include/"*.h          "$fw_dir/Headers/"
    cp "$LLAMA_CPP/tools/mtmd/mtmd.h"         "$fw_dir/Headers/"
    cp "$LLAMA_CPP/tools/mtmd/mtmd-helper.h"  "$fw_dir/Headers/"

    cat > "$fw_dir/Modules/module.modulemap" <<'MODULEMAP'
framework module llama {
    umbrella header "llama.h"
    header "mtmd.h"
    header "mtmd-helper.h"
    export *
    module * { export * }
}
MODULEMAP

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

    echo "── Slice $name done ──"
}

# ── Build both slices ──────────────────────────────────────────────────────
#                    name                sdk               archs            suffix            is_sim
build_slice "build-ios-device" "iphoneos"        "arm64"          "iphoneos"        "false"
build_slice "build-ios-sim"    "iphonesimulator" "arm64 x86_64"   "iphonesimulator" "true"

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
