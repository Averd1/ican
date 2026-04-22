import Foundation

/// Orchestrates all Layer 1 perception processing.
///
/// Runs three analyzers **concurrently** using Swift structured concurrency,
/// then fuses their outputs into a single `PerceptionResult`:
///
/// - `VisionService`     — OCR, scene classification, person detection (Apple Vision)
/// - `DepthEstimator`    — Depth Anything V2 CoreML (monocular depth map)
/// - `ObjectDetector`    — YOLOv3 Tiny CoreML (bounding boxes + labels)
///
/// If Depth Anything V2 or YOLOv3 are not bundled, their contributions
/// are simply omitted — the result still contains full Vision Framework data.
final class PerceptionLayer {

    static let shared = PerceptionLayer()
    private init() {}

    // MARK: - Public API

    /// Run the full Layer 1 pipeline on a JPEG image.
    /// All three analyzers are launched in parallel; total latency ≈ slowest individual model.
    func analyze(jpegData: Data) async -> PerceptionResult {
        // Concurrent execution — Swift structured concurrency
        async let visionDict  = VisionService.analyze(jpegData: jpegData)
        async let depthMap    = DepthEstimator.shared.estimateDepth(jpegData: jpegData)
        async let rawObjects  = ObjectDetector.shared.detectObjects(jpegData: jpegData)

        let vision  = await visionDict
        let depth   = await depthMap
        let objects = await rawObjects

        // Fuse YOLO detections with depth map samples
        let spatialObjects: [SpatialObject] = objects.map { obj in
            let center   = obj.normalizedCenter
            let bbox     = obj.imageSpaceBoundingBox
            let clock    = clockHour(from: center.x)
            let relDepth = depth.map {
                DepthEstimator.shared.sampleDepth($0, at: center)
            }
            return SpatialObject(
                label:              obj.label,
                confidence:         obj.confidence,
                normalizedCenterX:  Float(center.x),
                normalizedCenterY:  Float(center.y),
                clockPosition:      clock,
                relativeDepth:      relDepth,
                bboxX:              Float(bbox.origin.x),
                bboxY:              Float(bbox.origin.y),
                bboxW:              Float(bbox.width),
                bboxH:              Float(bbox.height)
            )
        }
        // Closest obstacles first
        .sorted { ($0.relativeDepth ?? 1.0) < ($1.relativeDepth ?? 1.0) }

        return PerceptionResult(
            ocrTexts:             vision["ocr_texts"]            as? [String] ?? [],
            sceneClassification:  vision["scene_classification"] as? String   ?? "unknown",
            sceneConfidence:      (vision["scene_confidence"]    as? NSNumber)?.floatValue ?? 0,
            personCount:          vision["person_count"]         as? Int       ?? 0,
            detectedObjects:      spatialObjects,
            hasDepthMap:          depth != nil
        )
    }

    // MARK: - Clock Mapping

    /// Map a normalised x coordinate [0, 1] to a clock hour.
    ///
    /// ```
    /// x ≈ 0.00 → 9 o'clock  (hard left)
    /// x ≈ 0.17 → 10 o'clock
    /// x ≈ 0.33 → 11 o'clock
    /// x ≈ 0.50 → 12 o'clock (straight ahead)
    /// x ≈ 0.67 → 1 o'clock
    /// x ≈ 0.83 → 2 o'clock
    /// x ≈ 1.00 → 3 o'clock  (hard right)
    /// ```
    private func clockHour(from normalizedX: CGFloat) -> Int {
        let hours = [9, 10, 11, 12, 1, 2, 3]
        let index = Int((normalizedX * CGFloat(hours.count - 1)).rounded())
        return hours[max(0, min(hours.count - 1, index))]
    }
}
