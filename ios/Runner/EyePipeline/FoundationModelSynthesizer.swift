import Foundation

/// Layer 3 — Synthesises a natural-language scene description from structured
/// Layer 1 + Layer 2 context using Apple Foundation Models (iOS 26+).
///
/// **Availability:** Requires an Apple Intelligence-enabled device running iOS 26+.
/// On unsupported devices `isAvailable` returns false and the caller falls back
/// to the enhanced template description from `PerceptionResult.toTemplateDescription()`.
///
/// **API note:** The `FoundationModels` framework ships with the iOS 26 / Xcode 26 SDK.
/// The `#if canImport(FoundationModels)` guards keep this file compiling on earlier
/// SDKs without changes. Upgrade the guarded block when targeting iOS 26+.
final class FoundationModelSynthesizer {

    static let shared = FoundationModelSynthesizer()
    private init() {}

    // MARK: - Availability

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // Runtime check — Apple Intelligence must be enabled and the system
            // language model must be downloaded on the device.
            return _foundationModelsAvailable()
        }
        #endif
        return false
    }

    // MARK: - Synthesis

    /// Generate a spoken scene description from structured context text.
    ///
    /// The `context` string comes from `PerceptionResult.toPromptContext()` and
    /// optionally includes a VLM caption. The `systemPrompt` is the shared
    /// spatial-awareness instruction used across all backends.
    ///
    /// Text is streamed sentence-by-sentence via `onToken` so TTS can begin
    /// before the full response is ready.
    func synthesize(
        context: String,
        systemPrompt: String,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            await _synthesizeWithFoundationModels(
                context:      context,
                systemPrompt: systemPrompt,
                onToken:      onToken,
                onComplete:   onComplete,
                onError:      onError
            )
            return
        }
        #endif
        onError("Foundation Models requires iOS 26 — falling back to template")
    }
}

// MARK: - iOS 26 Implementation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
private func _foundationModelsAvailable() -> Bool {
    if case .available = SystemLanguageModel.default.availability {
        return true
    }
    return false
}

@available(iOS 26.0, *)
private func _synthesizeWithFoundationModels(
    context:      String,
    systemPrompt: String,
    onToken:      @escaping (String) -> Void,
    onComplete:   @escaping () -> Void,
    onError:      @escaping (String) -> Void
) async {
    guard case .available = SystemLanguageModel.default.availability else {
        onError("Apple Intelligence is not available on this device")
        return
    }

    let session = LanguageModelSession(instructions: systemPrompt)
    let userPrompt = context.isEmpty
        ? "Describe this scene for a blind person."
        : "\(context)\n\nDescribe this scene for a blind person using clock positions for directions."

    do {
        let response = try await session.respond(to: userPrompt)
        let text = String(describing: response)

        // Split into sentences for TTS streaming
        var remaining = text[text.startIndex...]
        while let range = remaining.range(of: "[.!?] ", options: .regularExpression) {
            let sentence = String(remaining[remaining.startIndex..<range.upperBound])
            onToken(sentence)
            remaining = remaining[range.upperBound...]
        }
        if !remaining.isEmpty {
            onToken(String(remaining))
        }
        onComplete()
    } catch {
        onError(error.localizedDescription)
    }
}

#else

// Stub so the non-guarded call sites still compile on pre-iOS 26 SDKs.
private func _foundationModelsAvailable() -> Bool { false }

#endif
