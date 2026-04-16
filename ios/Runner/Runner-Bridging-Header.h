#import "GeneratedPluginRegistrant.h"

// llama.cpp C API — required for LlamaService.swift VLM inference.
// The llama.xcframework must be linked in the Xcode project build settings.
// Build llama.cpp with: -DGGML_METAL=ON -DBUILD_SHARED_LIBS=OFF
#if __has_include("llama.h")
#include "llama.h"
#include "llava.h"
#include "clip.h"
#endif
