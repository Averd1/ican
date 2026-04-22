import Foundation
import Vision
import UIKit

/// Wraps Apple Vision framework APIs for on-device image analysis.
/// Runs OCR, scene classification, and person detection in parallel on the Neural Engine.
final class VisionService {

    /// Analyze a JPEG image using Apple Vision framework.
    /// Returns structured results: OCR text, scene classification, and person count.
    static func analyze(jpegData: Data) async -> [String: Any] {
        guard let cgImage = UIImage(data: jpegData)?.cgImage else {
            return ["error": "Failed to decode JPEG image"]
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Create all three requests
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true

        let classificationRequest = VNClassifyImageRequest()

        let humanRequest = VNDetectHumanRectanglesRequest()
        if #available(iOS 15.0, *) {
            humanRequest.upperBodyOnly = false
        }

        // Run all requests in parallel on the Neural Engine
        do {
            try handler.perform([textRequest, classificationRequest, humanRequest])
        } catch {
            return ["error": "Vision analysis failed: \(error.localizedDescription)"]
        }

        // --- Extract OCR results ---
        var ocrTexts: [String] = []
        if let textResults = textRequest.results {
            for observation in textResults {
                if let candidate = observation.topCandidates(1).first,
                   candidate.confidence > 0.5 {
                    ocrTexts.append(candidate.string)
                }
            }
        }

        // --- Extract scene classification ---
        var sceneClassification = "unknown"
        var sceneConfidence: Float = 0.0
        if let classResults = classificationRequest.results {
            // Get top classification with reasonable confidence
            if let topResult = classResults.first, topResult.confidence > 0.15 {
                sceneClassification = topResult.identifier
                sceneConfidence = topResult.confidence
            }
        }

        // --- Extract person detection ---
        var personCount = 0
        var personRects: [[String: Double]] = []
        if let humanResults = humanRequest.results {
            personCount = humanResults.count
            for observation in humanResults {
                let box = observation.boundingBox
                personRects.append([
                    "x": Double(box.origin.x),
                    "y": Double(box.origin.y),
                    "w": Double(box.size.width),
                    "h": Double(box.size.height),
                ])
            }
        }

        return [
            "ocr_texts": ocrTexts,
            "scene_classification": sceneClassification,
            "scene_confidence": sceneConfidence,
            "person_count": personCount,
            "person_rects": personRects,
        ]
    }
}
