import Foundation

/// Wraps the llama.cpp C API for on-device VLM inference.
///
/// Manages model lifecycle (load/unload) and runs SmolVLM image+text inference
/// with Metal GPU acceleration. Designed for single-shot scene description,
/// not continuous inference.
///
/// **Prerequisites:**
/// - `llama.xcframework` must be linked in the Xcode project
/// - `#include "llama.h"` must be in the bridging header
/// - GGUF model files must exist in Documents/models/
final class LlamaService {

    static let shared = LlamaService()

    // Model file names (SmolVLM-500M-Instruct Q8_0)
    static let textModelFilename = "SmolVLM-500M-Instruct-Q8_0.gguf"
    static let visionProjectorFilename = "mmproj-SmolVLM-500M-Instruct-Q8_0.gguf"

    private var model: OpaquePointer?        // llama_model*
    private var context: OpaquePointer?      // llama_context*
    private var clipContext: OpaquePointer?   // clip_ctx* (vision projector)
    private var isLoaded = false

    private let contextSize: Int32 = 2048
    private let batchSize: Int32 = 512

    private init() {}

    // MARK: - Model Status

    /// Returns the current model status as a string for the MethodChannel.
    func getModelStatus() -> String {
        if isLoaded { return "loaded" }
        if modelsExistOnDisk() { return "ready" }
        return "not_downloaded"
    }

    /// Check if both GGUF files exist in the models directory.
    func modelsExistOnDisk() -> Bool {
        let modelsDir = Self.modelsDirectory()
        let textPath = modelsDir.appendingPathComponent(Self.textModelFilename).path
        let projPath = modelsDir.appendingPathComponent(Self.visionProjectorFilename).path
        return FileManager.default.fileExists(atPath: textPath)
            && FileManager.default.fileExists(atPath: projPath)
    }

    /// Returns the path to Documents/models/.
    static func modelsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("models", isDirectory: true)
    }

    // MARK: - Load / Unload

    /// Load the SmolVLM model into memory with Metal GPU acceleration.
    /// Returns true on success.
    func loadModel() async -> Bool {
        guard !isLoaded else { return true }

        // Check available memory before loading (~800MB needed)
        let availableMemory = os_proc_available_memory()
        let requiredMemory: UInt64 = 1_500_000_000 // 1.5 GB headroom
        if availableMemory < requiredMemory {
            print("[LlamaService] Insufficient memory: \(availableMemory / 1_000_000)MB available, need \(requiredMemory / 1_000_000)MB")
            return false
        }

        let modelsDir = Self.modelsDirectory()
        let textPath = modelsDir.appendingPathComponent(Self.textModelFilename).path
        let projPath = modelsDir.appendingPathComponent(Self.visionProjectorFilename).path

        guard FileManager.default.fileExists(atPath: textPath),
              FileManager.default.fileExists(atPath: projPath) else {
            print("[LlamaService] Model files not found at \(modelsDir.path)")
            return false
        }

        // Initialize llama backend
        llama_backend_init()

        // Load text model with Metal GPU offload
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99 // Offload all layers to Metal GPU

        guard let loadedModel = llama_model_load_from_file(textPath, modelParams) else {
            print("[LlamaService] Failed to load text model from \(textPath)")
            llama_backend_free()
            return false
        }
        model = loadedModel

        // Create inference context
        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(contextSize)
        ctxParams.n_batch = UInt32(batchSize)
        ctxParams.n_threads = UInt32(max(1, ProcessInfo.processInfo.processorCount - 2))

        guard let ctx = llama_init_from_model(loadedModel, ctxParams) else {
            print("[LlamaService] Failed to create context")
            llama_model_free(loadedModel)
            model = nil
            llama_backend_free()
            return false
        }
        context = ctx

        // Load vision projector (clip model)
        guard let clip = clip_model_load(projPath, 1) else {
            print("[LlamaService] Failed to load vision projector from \(projPath)")
            llama_free(ctx)
            llama_model_free(loadedModel)
            context = nil
            model = nil
            llama_backend_free()
            return false
        }
        clipContext = clip

        isLoaded = true
        print("[LlamaService] Model loaded successfully. Memory: \(os_proc_available_memory() / 1_000_000)MB available")
        return true
    }

    /// Unload the model and free all memory.
    func unloadModel() {
        guard isLoaded else { return }

        if let clip = clipContext {
            clip_free(clip)
            clipContext = nil
        }
        if let ctx = context {
            llama_free(ctx)
            context = nil
        }
        if let m = model {
            llama_model_free(m)
            model = nil
        }
        llama_backend_free()

        isLoaded = false
        print("[LlamaService] Model unloaded. Memory: \(os_proc_available_memory() / 1_000_000)MB available")
    }

    // MARK: - Inference

    /// Run image description inference.
    /// Streams tokens via the `onToken` callback.
    func describeImage(
        jpegData: Data,
        systemPrompt: String,
        visionContext: String?,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) async {
        guard isLoaded, let ctx = context, let mdl = model, let clip = clipContext else {
            onError("Model not loaded")
            return
        }

        // Build the full prompt with optional Vision framework context
        var fullPrompt = systemPrompt
        if let vc = visionContext, !vc.isEmpty {
            fullPrompt += "\n\n\(vc)\n\nDescribe this scene incorporating the context above."
        }

        // Process the image through the vision encoder
        // Create a temporary file for the JPEG data (llava API expects a file path)
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpImagePath = tmpDir.appendingPathComponent("vlm_input_\(UUID().uuidString).jpg")

        do {
            try jpegData.write(to: tmpImagePath)
        } catch {
            onError("Failed to write temp image: \(error.localizedDescription)")
            return
        }

        defer {
            try? FileManager.default.removeItem(at: tmpImagePath)
        }

        // Encode the image using the CLIP vision projector
        guard let imageEmbed = llava_image_embed_make_with_filename(
            clip, Int32(ProcessInfo.processInfo.processorCount),
            tmpImagePath.path
        ) else {
            onError("Failed to encode image with vision projector")
            return
        }

        defer {
            llava_image_embed_free(imageEmbed)
        }

        // Clear the KV cache for a fresh generation
        llama_kv_cache_clear(ctx)

        // Tokenize the system prompt
        let promptCStr = fullPrompt.cString(using: .utf8)!
        let maxTokens = Int32(fullPrompt.count + 256)
        var tokens = [llama_token](repeating: 0, count: Int(maxTokens))
        let nTokens = llama_tokenize(mdl, promptCStr, Int32(promptCStr.count - 1),
                                      &tokens, maxTokens, true, true)

        if nTokens < 0 {
            onError("Tokenization failed")
            return
        }

        // Evaluate prompt tokens in batches
        var batch = llama_batch_init(batchSize, 0, 1)
        defer { llama_batch_free(batch) }

        var nPast: Int32 = 0

        // First, embed the image tokens
        if !llava_eval_image_embed(ctx, imageEmbed, batchSize, &nPast) {
            onError("Failed to evaluate image embeddings")
            return
        }

        // Then evaluate the text prompt tokens
        let promptTokens = Array(tokens[0..<Int(nTokens)])
        for i in stride(from: 0, to: promptTokens.count, by: Int(batchSize)) {
            let end = min(i + Int(batchSize), promptTokens.count)
            let chunk = Array(promptTokens[i..<end])

            batch.n_tokens = 0
            for (j, token) in chunk.enumerated() {
                let pos = nPast + Int32(j)
                let isLast = (i + j == promptTokens.count - 1)
                llama_batch_add(&batch, token, pos, [0], isLast)
            }

            if llama_decode(ctx, batch) != 0 {
                onError("Failed to decode prompt batch")
                return
            }
            nPast += Int32(chunk.count)
        }

        // Generate response tokens autoregressively
        let maxGenTokens = 500
        let eosToken = llama_token_eos(mdl)

        for _ in 0..<maxGenTokens {
            // Sample next token
            let logits = llama_get_logits_ith(ctx, batch.n_tokens - 1)!
            let nVocab = llama_n_vocab(mdl)

            var candidates = (0..<nVocab).map { i in
                llama_token_data(id: i, logit: logits[Int(i)], p: 0.0)
            }

            var candidatesP = llama_token_data_array(
                data: &candidates, size: Int(nVocab), selected: -1, sorted: false
            )

            // Temperature sampling (conservative for scene description)
            llama_sample_temp(ctx, &candidatesP, 0.2)
            llama_sample_top_p(ctx, &candidatesP, 0.8, 1)
            let newToken = llama_sample_token(ctx, &candidatesP)

            // Check for end-of-sequence
            if newToken == eosToken {
                break
            }

            // Convert token to text
            var buf = [CChar](repeating: 0, count: 256)
            let len = llama_token_to_piece(mdl, newToken, &buf, 256, 0, true)
            if len > 0 {
                let tokenStr = String(cString: buf)
                onToken(tokenStr)
            }

            // Evaluate the new token for next prediction
            batch.n_tokens = 0
            llama_batch_add(&batch, newToken, nPast, [0], true)
            nPast += 1

            if llama_decode(ctx, batch) != 0 {
                onError("Decode failed during generation")
                return
            }
        }

        onComplete()
    }
}

// MARK: - llama_batch helper

private extension llama_batch {
    /// Add a token to the batch.
    mutating func add(_ token: llama_token, _ pos: Int32, _ seqIds: [Int32], _ logits: Bool) {
        let i = Int(n_tokens)
        self.token[i] = token
        self.pos[i] = pos
        self.n_seq_id[i] = Int32(seqIds.count)
        for (j, id) in seqIds.enumerated() {
            self.seq_id[i]![j] = id
        }
        self.logits[i] = logits ? 1 : 0
        n_tokens += 1
    }
}
