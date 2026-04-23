#import "GeneratedPluginRegistrant.h"

// llama.cpp C API — required for LlamaService.swift VLM inference.
// Build the xcframework: scripts/build_llama_ios.sh ~/path/to/llama.cpp
// Then add ios/Frameworks/llama.xcframework to the Runner target in Xcode.
#if __has_include("llama.h")
#include "llama.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#endif
