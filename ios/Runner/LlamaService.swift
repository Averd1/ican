import Foundation

/// Wraps the llama.cpp mtmd C API for SmolVLM-500M on-device multimodal inference.
///
/// **Setup required before this works:**
/// 1. Build llama.xcframework: `./scripts/build_llama_ios.sh ~/path/to/llama.cpp`
/// 2. Add ios/Frameworks/llama.xcframework to the Runner target in Xcode
/// 3. Download model files via ModelDownloadManager (or manually place in Documents/models/)
///
/// **Fallback behaviour:** All public methods fail gracefully when the framework
/// is not linked or model files are absent — the app falls through to
/// FoundationModelSynthesizer or the template description.
final class LlamaService {

    static let shared = LlamaService()

    static let textModelFilename      = "SmolVLM-500M-Instruct-Q8_0.gguf"
    static let visionProjectorFilename = "mmproj-SmolVLM-500M-Instruct-Q8_0.gguf"

    // llama.cpp context handles (OpaquePointer wraps C struct pointers)
    private var llamaModel: OpaquePointer?
    private var llamaCtx:   OpaquePointer?
    private var mtmdCtx:    OpaquePointer?
    private var isLoaded    = false

    private init() {}

    // MARK: - Status

    func getModelStatus() -> String {
        if isLoaded       { return "loaded" }
        if modelsExistOnDisk() { return "ready" }
        return "not_downloaded"
    }

    func modelsExistOnDisk() -> Bool {
        let dir = Self.modelsDirectory()
        let textPath = dir.appendingPathComponent(Self.textModelFilename).path
        let projPath = dir.appendingPathComponent(Self.visionProjectorFilename).path
        return FileManager.default.fileExists(atPath: textPath)
            && FileManager.default.fileExists(atPath: projPath)
    }

    static func modelsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("models", isDirectory: true)
    }

    // MARK: - Lifecycle

    func loadModel() async -> Bool {
        #if canImport(llama)
        guard !isLoaded else { return true }
        guard modelsExistOnDisk() else {
            print("[LlamaService] Model files not on disk")
            return false
        }

        let dir      = Self.modelsDirectory()
        let textPath = dir.appendingPathComponent(Self.textModelFilename).path
        let projPath = dir.appendingPathComponent(Self.visionProjectorFilename).path

        return await Task.detached(priority: .userInitiated) {
            // ── 1. Load text model onto Metal GPU ────────────────────────────
            var mparams         = llama_model_default_params()
            mparams.n_gpu_layers = 99        // offload all layers to Metal
            guard let model = llama_model_load_from_file(textPath, mparams) else {
                print("[LlamaService] Failed to load text model from \(textPath)")
                return false
            }

            // ── 2. Create inference context ───────────────────────────────────
            var cparams          = llama_context_default_params()
            cparams.n_ctx        = 4096
            cparams.n_batch      = 512
            cparams.n_threads    = 4
            guard let ctx = llama_init_from_model(model, cparams) else {
                llama_model_free(model)
                print("[LlamaService] Failed to create llama context")
                return false
            }

            // ── 3. Load vision projector (mtmd) ───────────────────────────────
            var mmparams            = mtmd_context_params_default()
            mmparams.use_gpu        = true
            mmparams.n_threads      = 4
            mmparams.print_timings  = false
            guard let mctx = mtmd_init_from_file(projPath, model, mmparams) else {
                llama_free(ctx)
                llama_model_free(model)
                print("[LlamaService] Failed to load vision projector from \(projPath)")
                return false
            }

            self.llamaModel = model
            self.llamaCtx   = ctx
            self.mtmdCtx    = mctx
            self.isLoaded   = true
            print("[LlamaService] SmolVLM-500M loaded — ready for inference")
            return true
        }.value
        #else
        print("[LlamaService] llama.xcframework not linked")
        return false
        #endif
    }

    func unloadModel() {
        #if canImport(llama)
        if let mctx = mtmdCtx   { mtmd_free(mctx);         mtmdCtx   = nil }
        if let ctx  = llamaCtx  { llama_free(ctx);          llamaCtx  = nil }
        if let m    = llamaModel { llama_model_free(m);     llamaModel = nil }
        #endif
        isLoaded = false
        print("[LlamaService] Model unloaded")
    }

    // MARK: - Inference

    func describeImage(
        jpegData:      Data,
        systemPrompt:  String,
        visionContext: String?,
        onToken:       @escaping (String) -> Void,
        onComplete:    @escaping () -> Void,
        onError:       @escaping (String) -> Void
    ) async {
        #if canImport(llama)
        guard isLoaded,
              let model = llamaModel,
              let ctx   = llamaCtx,
              let mctx  = mtmdCtx
        else {
            onError("SmolVLM not loaded — call loadModel() first")
            return
        }

        await Task.detached(priority: .userInitiated) {
            // ── 1. Decode JPEG → RGB bitmap ────────────────────────────────────
            guard let bitmap: OpaquePointer = jpegData.withUnsafeBytes({ rawBuf in
                guard let ptr = rawBuf.baseAddress else { return nil }
                return mtmd_helper_bitmap_init_from_buf(
                    mctx,
                    ptr.assumingMemoryBound(to: UInt8.self),
                    jpegData.count
                )
            }) else {
                onError("Failed to decode image")
                return
            }
            defer { mtmd_bitmap_free(bitmap) }

            // ── 2. Build prompt with <image> marker ────────────────────────────
            let marker  = String(cString: mtmd_default_marker())
            let userMsg = visionContext.map { "\($0)\n\nDescribe this scene." }
                       ?? "Describe this scene for a blind person. Use clock positions (12 o'clock = straight ahead, 3 o'clock = right, 9 o'clock = left). Be concise."
            let fullPrompt = "\(marker)\n\(userMsg)"

            // ── 3. Tokenize (interleaves text + image tokens) ──────────────────
            guard let chunks = mtmd_input_chunks_init() else {
                onError("Failed to init input chunks")
                return
            }
            defer { mtmd_input_chunks_free(chunks) }

            var tokenizeOk: Int32 = -1
            fullPrompt.withCString { cStr in
                var inputText          = mtmd_input_text()
                inputText.text         = cStr
                inputText.add_special  = true
                inputText.parse_special = true

                // mtmd_tokenize expects const mtmd_bitmap **bitmaps
                var bitmapPtr: OpaquePointer? = bitmap
                withUnsafeMutablePointer(to: &bitmapPtr) { bitmapPtrPtr in
                    tokenizeOk = mtmd_tokenize(mctx, chunks, &inputText,
                                               bitmapPtrPtr, 1)
                }
            }
            guard tokenizeOk == 0 else {
                onError("Tokenize failed: \(tokenizeOk)")
                return
            }

            // ── 4. Encode image + prefill text into KV cache ───────────────────
            var nPast: llama_pos = 0
            let evalRet = mtmd_helper_eval_chunks(mctx, ctx, chunks,
                                                  0, 0, 512, true, &nPast)
            guard evalRet == 0 else {
                onError("Image eval failed: \(evalRet)")
                return
            }

            // ── 5. Build sampler chain ─────────────────────────────────────────
            guard let samplerChain = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
                onError("Failed to create sampler")
                return
            }
            defer { llama_sampler_free(samplerChain) }

            llama_sampler_chain_add(samplerChain, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(samplerChain, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(samplerChain, llama_sampler_init_temp(0.7))
            llama_sampler_chain_add(samplerChain,
                llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))

            let vocab = llama_model_get_vocab(model)

            // ── 6. Autoregressive generation ───────────────────────────────────
            var pieceBuf = [CChar](repeating: 0, count: 256)
            var generated = 0
            let maxTokens = 300

            while generated < maxTokens {
                let tokenId = llama_sampler_sample(samplerChain, ctx, -1)
                llama_sampler_accept(samplerChain, tokenId)

                if llama_vocab_is_eog(vocab, tokenId) { break }

                // Decode token → text piece and stream it
                let n = llama_token_to_piece(vocab, tokenId,
                                             &pieceBuf, Int32(pieceBuf.count),
                                             0, false)
                if n > 0 {
                    let bytes = pieceBuf[0..<Int(n)].map { UInt8(bitPattern: $0) }
                    if let piece = String(bytes: bytes, encoding: .utf8), !piece.isEmpty {
                        onToken(piece)
                    }
                }

                // Feed token back for next step
                var tid = tokenId
                withUnsafeMutablePointer(to: &tid) { tidPtr in
                    var batch = llama_batch_get_one(tidPtr, 1)
                    llama_decode(ctx, batch)
                }
                nPast += 1
                generated += 1
            }

            // ── 7. Reset KV cache for next call ────────────────────────────────
            llama_kv_self_clear(ctx)
            onComplete()
        }.value
        #else
        onError("SmolVLM not available — llama.xcframework not linked")
        #endif
    }
}
