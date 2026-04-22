import Foundation

/// Wraps the llama.cpp C API for on-device VLM inference.
///
/// **Prerequisites:**
/// - `llama.xcframework` must be linked in the Xcode project
/// - `#include "llama.h"` must be in the bridging header
/// - GGUF model files must exist in Documents/models/
///
/// This entire file is conditionally compiled: when llama.h is not available
/// (no xcframework linked), a no-op stub is compiled instead.

// MARK: - Stub (no llama.xcframework)

/// Stub implementation when llama.cpp is not linked.
/// All methods return "not available" so the app gracefully falls back
/// to other vision backends (Moondream CoreML, Foundation Models, Cloud).
final class LlamaService {

    static let shared = LlamaService()

    static let textModelFilename = "SmolVLM-500M-Instruct-Q8_0.gguf"
    static let visionProjectorFilename = "mmproj-SmolVLM-500M-Instruct-Q8_0.gguf"

    private init() {}

    func getModelStatus() -> String {
        if modelsExistOnDisk() { return "ready" }
        return "not_downloaded"
    }

    func modelsExistOnDisk() -> Bool {
        let modelsDir = Self.modelsDirectory()
        let textPath = modelsDir.appendingPathComponent(Self.textModelFilename).path
        let projPath = modelsDir.appendingPathComponent(Self.visionProjectorFilename).path
        return FileManager.default.fileExists(atPath: textPath)
            && FileManager.default.fileExists(atPath: projPath)
    }

    static func modelsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("models", isDirectory: true)
    }

    func loadModel() async -> Bool {
        print("[LlamaService] llama.xcframework not linked — SmolVLM unavailable")
        return false
    }

    func unloadModel() {}

    func describeImage(
        jpegData: Data,
        systemPrompt: String,
        visionContext: String?,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) async {
        onError("SmolVLM not available — llama.xcframework not linked")
    }
}
