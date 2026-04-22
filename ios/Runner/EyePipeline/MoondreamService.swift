import CoreML
import Foundation
import UIKit

// MARK: - MoondreamService

/// On-device Moondream 2B inference via CoreML.
///
/// **Required bundle files** (add via Xcode "Add Files to Runner"):
///   moondream_vision.mlpackage          — vision encoder (done, 215 MB)
///   moondream_prefill.mlpackage         — batch prefill for BOS+image tokens
///   moondream_text.mlpackage            — stateful single-step text decoder (iOS 18+)
///   moondream_coord_encoder.mlpackage   — Pointing: coord → embedding
///   moondream_coord_decoder.mlpackage   — Pointing: hidden → (x,y) logits
///   moondream_size_decoder.mlpackage    — Detection: hidden → (w,h) logits
///   moondream_token_embeddings.bin      — pre-extracted float16 token embeddings
///   moondream_tokens.json               — token ID → index mapping + templates
///
/// **Usage:**
///   let md = MoondreamService.shared
///   guard md.isAvailable else { return }
///   let ok = await md.encodeAndPrefill(jpegData: jpeg)
///   await md.caption(onToken: { print($0) }, onComplete: {}, onError: { _ in })
final class MoondreamService {

    static let shared = MoondreamService()

    // MARK: - Models

    private var visionModel:       MLModel?
    private var prefillModel:      MLModel?
    private var textDecodeModel:   MLModel?
    private var coordEncModel:     MLModel?
    private var coordDecModel:     MLModel?
    private var sizeDecModel:      MLModel?

    // Stateful KV cache for the decode model (iOS 18+)
    private var decodeState: AnyObject?   // MLState, type-erased for pre-iOS 18 builds

    // MARK: - Token data

    private var tokenIndex:     [Int: Int] = [:]   // token_id → row in embedding matrix
    private var embeddings:     UnsafeMutableRawPointer?  // (N, 2048) float16 bytes
    private var embeddingsF16:  Bool = false
    private var nTokens:        Int = 0
    private var tokenTemplates: [String: [Int]] = [:]
    private var objectTokens:   [String: [Int]] = [:]
    private var bosId:          Int = 50256
    private var eosId:          Int = 50256

    // Constants from config_md2.json
    private let dim        = 2048
    private let nHeads     = 32
    private let nKVHeads   = 32
    private let maxContext = 2048
    private let prefillLen = 730   // 1 BOS + 729 image tokens
    private let vocabSize  = 51200

    private init() {}

    deinit { embeddings?.deallocate() }

    // MARK: - Availability

    var isAvailable: Bool {
        visionModel != nil && prefillModel != nil && textDecodeModel != nil
    }

    var isLoaded: Bool { isAvailable }

    // MARK: - Loading

    /// Load all CoreML models and token data from the app bundle.
    /// Safe to call multiple times (no-op if already loaded).
    func loadModels() {
        guard visionModel == nil else { return }

        let config = MLModelConfiguration()
        config.computeUnits = .all

        visionModel    = loadModel("moondream_vision",          config: config)
        prefillModel   = loadModel("moondream_prefill",         config: config)
        textDecodeModel = loadModel("moondream_text",           config: config)
        coordEncModel  = loadModel("moondream_coord_encoder",   config: config)
        coordDecModel  = loadModel("moondream_coord_decoder",   config: config)
        sizeDecModel   = loadModel("moondream_size_decoder",    config: config)

        if #available(iOS 18.0, *), let tm = textDecodeModel {
            decodeState = try? tm.makeState()
        }

        loadTokenData()

        let status = isAvailable ? "ready" : "partial (some models missing)"
        print("[MoondreamService] \(status)")
    }

    private func loadModel(_ name: String, config: MLModelConfiguration) -> MLModel? {
        if let url = Bundle.main.url(forResource: name, withExtension: "mlpackage")
                  ?? Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            return try? MLModel(contentsOf: url, configuration: config)
        }
        print("[MoondreamService] \(name) not found in bundle")
        return nil
    }

    private func loadTokenData() {
        guard let jsonURL = Bundle.main.url(forResource: "moondream_tokens", withExtension: "json"),
              let binURL  = Bundle.main.url(forResource: "moondream_token_embeddings", withExtension: "bin"),
              let jsonData = try? Data(contentsOf: jsonURL),
              let meta = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("[MoondreamService] Token data not found")
            return
        }

        if let special = meta["special"] as? [String: Int] {
            bosId = special["bos"] ?? 50256
            eosId = special["eos"] ?? 50256
        }
        if let idxMap = meta["token_id_to_index"] as? [String: Int] {
            tokenIndex = Dictionary(uniqueKeysWithValues: idxMap.compactMap { k, v in
                Int(k).map { ($0, v) }
            })
            nTokens = idxMap.count
        }
        if let tmpl = meta["templates"] as? [String: [Int]] {
            tokenTemplates = tmpl
        }
        if let objs = meta["objects"] as? [String: [Int]] {
            objectTokens = objs
        }

        let binData = (try? Data(contentsOf: binURL)) ?? Data()
        guard binData.count == nTokens * dim * 2 else {
            print("[MoondreamService] Embedding binary size mismatch")
            return
        }
        embeddings = UnsafeMutableRawPointer.allocate(byteCount: nTokens * dim * 2, alignment: 2)
        binData.withUnsafeBytes { ptr in
            embeddings!.copyMemory(from: ptr.baseAddress!, byteCount: nTokens * dim * 2)
        }
        embeddingsF16 = true
        print("[MoondreamService] Token data loaded: \(nTokens) embeddings")
    }

    // MARK: - Public Inference API

    /// Encode an image and run the 730-token prefill, filling the KV cache.
    /// Must be called before caption() or point().
    func encodeAndPrefill(jpegData: Data) async -> Bool {
        guard let vision = visionModel, let prefill = prefillModel else { return false }

        // 1. Vision encoder → (729, 2048) image embeddings
        guard let cgImage = UIImage(data: jpegData)?.cgImage else { return false }

        guard let imageCrop = makeInputArray(shape: [1, 3, 378, 378]),
              let _ = fillNormalisedImage(cgImage, into: imageCrop) else { return false }

        guard let visionOut = try? vision.prediction(from: MLDictionaryFeatureProvider(
            dictionary: ["image_crop": MLFeatureValue(multiArray: imageCrop)])),
              let imageEmbeds = visionOut.featureValue(for: "image_embeddings")?.multiArrayValue
        else { return false }

        // imageEmbeds shape: (729, 2048)

        // 2. Build prefill input: BOS(1) + image(729) = (1, 730, 2048)
        guard let prefillInput = buildPrefillInput(bosId: bosId, imageEmbeds: imageEmbeds) else {
            return false
        }

        // 3. Run prefill model
        guard let prefillOut = try? prefill.prediction(from: MLDictionaryFeatureProvider(
            dictionary: ["embeds": MLFeatureValue(multiArray: prefillInput)])) else {
            return false
        }

        // 4. Transfer KV caches from prefill output into decode model's state
        if #available(iOS 18.0, *), let state = decodeState as? MLState {
            guard loadKVIntoState(prefillOut, state: state) else { return false }
        }

        return true
    }

    /// Generate a scene caption, streaming tokens via onToken.
    func caption(
        onToken:    @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError:    @escaping (String) -> Void
    ) async {
        guard isAvailable else { onError("Moondream models not loaded"); return }
        guard #available(iOS 18.0, *), let state = decodeState as? MLState else {
            onError("Stateful decode requires iOS 18")
            return
        }

        let templateIds = tokenTemplates["caption_normal"] ?? [198, 198, 24334, 1159, 25]
        await generateText(
            promptIds: templateIds,
            startPos:  prefillLen,
            state:     state,
            onToken:   onToken,
            onComplete: onComplete,
            onError:   onError
        )
    }

    /// Point to a named object — returns normalised (x, y) coordinates.
    /// objectName should be a single navigation noun, e.g. "door", "person".
    func point(
        objectName: String,
        onResult:   @escaping ([(x: Float, y: Float)]) -> Void,
        onError:    @escaping (String) -> Void
    ) async {
        guard isAvailable,
              let coordDec = coordDecModel else { onError("Models not loaded"); return }
        guard #available(iOS 18.0, *), let state = decodeState as? MLState else {
            onError("Requires iOS 18"); return
        }

        // Look up object token IDs from pre-tokenized table
        let objIds = objectTokens[objectName] ?? objectTokens[objectName.lowercased()] ?? []
        guard !objIds.isEmpty else { onError("Unknown object: \(objectName)"); return }

        let prefixIds = tokenTemplates["point_prefix"] ?? [198, 198, 12727, 25]
        let suffixIds = tokenTemplates["point_suffix"] ?? [628]
        let promptIds = prefixIds + objIds + suffixIds

        var pos = prefillLen
        var attnMask = makeAttnMask(validUpTo: pos)

        // Run prompt tokens; capture the last hidden state for coord decoding
        var lastHidden: MLMultiArray?
        for tokenId in promptIds {
            guard let embed = tokenEmbedding(tokenId) else { continue }
            lastHidden = runDecodeStep(embed: embed, pos: pos, mask: attnMask, state: state)
            attnMask[[0, 0, 0, pos] as [NSNumber]] = 0.0
            pos += 1
        }

        guard let lastHidden else { onError("No hidden state from prompt tokens"); return }

        var points: [(x: Float, y: Float)] = []
        var continueDecoding = true

        while continueDecoding {
            // Decode x coordinate
            guard let xLogits = runCoordDecode(hidden: lastHidden, model: coordDec) else { break }
            let xCoord = argmax(xLogits) / Float(xLogits.count)

            // Encode x and decode y
            guard let xEnc = runCoordEncode(coord: xCoord),
                  let xHidden = runDecodeStep(embed: xEnc, pos: pos, mask: attnMask, state: state)
            else { break }
            attnMask[[0, 0, 0, pos] as [NSNumber]] = 0.0
            pos += 1

            guard let yLogits = runCoordDecode(hidden: xHidden, model: coordDec) else { break }
            let yCoord = argmax(yLogits) / Float(yLogits.count)

            points.append((x: xCoord, y: yCoord))

            // Check next token — coord_id (continue) or eos (stop)
            guard let yEnc = runCoordEncode(coord: yCoord),
                  let (nextLogits, _) = runDecodeStepFull(embed: yEnc, pos: pos, mask: attnMask, state: state)
            else { break }
            attnMask[[0, 0, 0, pos] as [NSNumber]] = 0.0
            pos += 1

            let nextToken = argmaxInt(nextLogits)
            continueDecoding = (nextToken != eosId) && points.count < 20
        }

        onResult(points)
    }

    // MARK: - Private: Text Generation

    private func generateText(
        promptIds:  [Int],
        startPos:   Int,
        state:      AnyObject,
        onToken:    @escaping (String) -> Void,
        onComplete: @escaping () -> Void,
        onError:    @escaping (String) -> Void
    ) async {
        guard #available(iOS 18.0, *), let mlState = state as? MLState else { return }

        var pos = startPos
        var attnMask = makeAttnMask(validUpTo: pos)

        // Prefill prompt tokens
        var lastLogits: MLMultiArray?
        for tokenId in promptIds {
            guard let embed = tokenEmbedding(tokenId) else { continue }
            guard let (logits, _) = runDecodeStepFull(
                embed: embed, pos: pos, mask: attnMask, state: mlState) else { continue }
            attnMask[[0, 0, 0, pos] as [NSNumber]] = 0.0
            pos += 1
            lastLogits = logits
        }

        guard var logits = lastLogits else { onError("Prompt prefill failed"); return }

        // Autoregressive decode
        var tokenCache: [Int] = []
        for _ in 0..<768 {
            let nextId = argmaxInt(logits)
            if nextId == eosId || nextId == bosId { break }

            tokenCache.append(nextId)
            if let piece = detokenize(tokenCache) {
                onToken(piece)
                tokenCache = []
            }

            guard let embed = tokenEmbedding(nextId) else { break }
            guard let (nextLogits, _) = runDecodeStepFull(
                embed: embed, pos: pos, mask: attnMask, state: mlState) else { break }
            attnMask[[0, 0, 0, pos] as [NSNumber]] = 0.0
            pos += 1
            logits = nextLogits
        }

        // Flush remaining tokens
        if !tokenCache.isEmpty, let remaining = detokenize(tokenCache) {
            onToken(remaining)
        }
        onComplete()
    }

    // MARK: - Private: Decode Steps

    private var lastHiddenState: MLMultiArray?

    @discardableResult
    private func runDecodeStep(
        embed: MLMultiArray,
        pos:   Int,
        mask:  MLMultiArray,
        state: AnyObject
    ) -> MLMultiArray? {
        let (_, hidden) = runDecodeStepFull(embed: embed, pos: pos, mask: mask, state: state) ?? (nil, nil)
        return hidden
    }

    private func runDecodeStepFull(
        embed: MLMultiArray,
        pos:   Int,
        mask:  MLMultiArray,
        state: AnyObject
    ) -> (MLMultiArray, MLMultiArray)? {
        guard #available(iOS 18.0, *),
              let model = textDecodeModel,
              let mlState = state as? MLState else { return nil }

        guard let posArray = makeInt32Array(value: Int32(pos), shape: [1]) else { return nil }

        let dict: [String: Any] = [
            "token_embed": MLFeatureValue(multiArray: embed),
            "pos_id":      MLFeatureValue(multiArray: posArray),
            "attn_mask":   MLFeatureValue(multiArray: mask),
        ]
        guard let input = try? MLDictionaryFeatureProvider(dictionary: dict),
              let output = try? model.prediction(from: input, using: mlState),
              let logits = output.featureValue(for: "logits")?.multiArrayValue,
              let hidden = output.featureValue(for: "hidden_state")?.multiArrayValue
        else { return nil }

        lastHiddenState = hidden
        return (logits, hidden)
    }

    // MARK: - Private: Coord / Size Heads

    private func runCoordEncode(coord: Float) -> MLMultiArray? {
        guard let model = coordEncModel else { return nil }
        guard let input = makeFloat32Array(values: [coord], shape: [1]) else { return nil }
        let dict = ["coord": MLFeatureValue(multiArray: input)]
        guard let fp = try? MLDictionaryFeatureProvider(dictionary: dict),
              let out = try? model.prediction(from: fp) else { return nil }
        return out.featureValue(for: "coord_embedding")?.multiArrayValue
    }

    private func runCoordDecode(hidden: MLMultiArray, model: MLModel) -> [Float]? {
        let dict = ["hidden": MLFeatureValue(multiArray: hidden)]
        guard let fp = try? MLDictionaryFeatureProvider(dictionary: dict),
              let out = try? model.prediction(from: fp),
              let logits = out.featureValue(for: "coord_logits")?.multiArrayValue else { return nil }
        return (0..<logits.count).map { logits[$0].floatValue }
    }

    // MARK: - Private: KV Cache Transfer

    private func loadKVIntoState(_ prefillOut: MLFeatureProvider, state: AnyObject) -> Bool {
        // TODO: Implement KV cache transfer once Moondream CoreML models are bundled.
        // Uses MLState.getMultiArray(forStateNamed:handler:) to write prefill KV
        // outputs into the decode model's stateful cache buffers.
        print("[MoondreamService] KV cache transfer not yet implemented — models not bundled")
        return false
    }

    // MARK: - Private: Tokenization / Embeddings

    private func tokenEmbedding(_ tokenId: Int) -> MLMultiArray? {
        guard let idx = tokenIndex[tokenId], let embs = embeddings else { return nil }
        guard let arr = try? MLMultiArray(shape: [1, 1, dim] as [NSNumber], dataType: .float32) else {
            return nil
        }
        let dst = arr.dataPointer.bindMemory(to: Float32.self, capacity: dim)
        let src = embs.advanced(by: idx * dim * 2).bindMemory(to: UInt16.self, capacity: dim)
        for j in 0..<dim {
            let bits = src[j]
            dst[j] = float16BitsToFloat(bits)
        }
        return arr
    }

    private func float16BitsToFloat(_ bits: UInt16) -> Float {
        let sign     = UInt32((bits >> 15) & 0x1)
        let exponent = UInt32((bits >> 10) & 0x1F)
        let mantissa = UInt32(bits & 0x3FF)

        var result: UInt32
        if exponent == 0 {
            if mantissa == 0 { result = sign << 31 }
            else {
                var e = exponent
                var m = mantissa
                while (m & 0x400) == 0 { m <<= 1; e -= 1 }
                e += 1; m &= ~UInt32(0x400)
                result = (sign << 31) | ((e + 112) << 23) | (m << 13)
            }
        } else if exponent == 31 {
            result = (sign << 31) | (0xFF << 23) | (mantissa << 13)
        } else {
            result = (sign << 31) | ((exponent + 112) << 23) | (mantissa << 13)
        }
        return Float(bitPattern: result)
    }

    // Minimal GPT-2 style detokenizer: handles Ġ → space, Ċ → newline
    private func detokenize(_ ids: [Int]) -> String? {
        // Load vocab on first call
        if vocabReverse.isEmpty { loadVocab() }
        let pieces = ids.compactMap { vocabReverse[$0] }
        guard !pieces.isEmpty else { return nil }
        return pieces.joined()
            .replacingOccurrences(of: "Ġ", with: " ")
            .replacingOccurrences(of: "Ċ", with: "\n")
    }

    private var vocabReverse: [Int: String] = [:]

    private func loadVocab() {
        guard let url  = Bundle.main.url(forResource: "vocab", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Int] else { return }
        vocabReverse = Dictionary(uniqueKeysWithValues: dict.map { ($1, $0) })
    }

    // MARK: - Private: Prefill Input

    private func buildPrefillInput(bosId: Int, imageEmbeds: MLMultiArray) -> MLMultiArray? {
        // Concatenate BOS embedding (1, 2048) + image embeddings (729, 2048) → (1, 730, 2048)
        guard let bosEmb = tokenEmbedding(bosId) else { return nil }
        guard let result = try? MLMultiArray(shape: [1, 730, dim] as [NSNumber], dataType: .float32)
        else { return nil }

        let dst = result.dataPointer.bindMemory(to: Float32.self, capacity: 730 * dim)
        let bosPtr = bosEmb.dataPointer.bindMemory(to: Float32.self, capacity: dim)
        // Row 0: BOS
        memcpy(dst, bosPtr, dim * 4)
        // Rows 1..729: image embeddings
        let imgPtr = imageEmbeds.dataPointer.bindMemory(to: Float32.self, capacity: 729 * dim)
        memcpy(dst.advanced(by: dim), imgPtr, 729 * dim * 4)
        return result
    }

    // MARK: - Private: Attention Mask

    /// Additive attention mask: 0.0 = attend, -inf = ignore.
    /// All positions 0..<validUpTo are unmasked.
    private func makeAttnMask(validUpTo pos: Int) -> MLMultiArray {
        let mask = try! MLMultiArray(shape: [1, 1, 1, maxContext] as [NSNumber], dataType: .float32)
        let ptr  = mask.dataPointer.bindMemory(to: Float32.self, capacity: maxContext)
        for i in 0..<maxContext { ptr[i] = i < pos ? 0.0 : Float.infinity * -1.0 }
        return mask
    }

    // MARK: - Private: Image Preprocessing

    /// Fill a (1, 3, 378, 378) float32 MLMultiArray from a CGImage.
    /// Normalises to [-1, 1] (matching Moondream's training preprocessing).
    @discardableResult
    private func fillNormalisedImage(_ image: CGImage, into array: MLMultiArray) -> MLMultiArray? {
        let size = 378
        let ctx  = CGContext(data: nil, width: size, height: size,
                             bitsPerComponent: 8, bytesPerRow: size * 4,
                             space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let pixels = ctx.data else { return nil }

        let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: 3 * size * size)
        let src = pixels.bindMemory(to: UInt8.self, capacity: size * size * 4)

        for y in 0..<size {
            for x in 0..<size {
                let pix = (y * size + x) * 4
                ptr[0 * size * size + y * size + x] = (Float(src[pix])     / 255.0 - 0.5) / 0.5
                ptr[1 * size * size + y * size + x] = (Float(src[pix + 1]) / 255.0 - 0.5) / 0.5
                ptr[2 * size * size + y * size + x] = (Float(src[pix + 2]) / 255.0 - 0.5) / 0.5
            }
        }
        return array
    }

    // MARK: - Private: Array Helpers

    private func makeInputArray(shape: [Int]) -> MLMultiArray? {
        try? MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float32)
    }

    private func makeFloat32Array(values: [Float], shape: [Int]) -> MLMultiArray? {
        guard let arr = try? MLMultiArray(shape: shape.map { NSNumber(value: $0) },
                                          dataType: .float32) else { return nil }
        let ptr = arr.dataPointer.bindMemory(to: Float32.self, capacity: values.count)
        for (i, v) in values.enumerated() { ptr[i] = v }
        return arr
    }

    private func makeInt32Array(value: Int32, shape: [Int]) -> MLMultiArray? {
        guard let arr = try? MLMultiArray(shape: shape.map { NSNumber(value: $0) },
                                          dataType: .int32) else { return nil }
        arr[0] = NSNumber(value: value)
        return arr
    }

    private func argmax(_ values: [Float]) -> Float {
        var bestIdx = 0
        var bestVal = values[0]
        for (i, v) in values.enumerated() { if v > bestVal { bestVal = v; bestIdx = i } }
        return Float(bestIdx)
    }

    private func argmaxInt(_ arr: MLMultiArray) -> Int {
        var best = 0
        var bestVal = arr[0].floatValue
        for i in 1..<arr.count {
            let v = arr[i].floatValue
            if v > bestVal { bestVal = v; best = i }
        }
        return best
    }
}
