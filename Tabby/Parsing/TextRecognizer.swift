import UIKit
import Vision

/// On-device OCR using Apple's Vision framework. No network, no API keys.
enum TextRecognizer {
    /// Recognized text rows across all pages, top to bottom.
    static func rows(in images: [UIImage]) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            var rows: [String] = []
            for image in images {
                let found = try TextRecognizer.fragments(in: image)
                rows += ReceiptParser.rows(from: found)
            }
            return rows
        }.value
    }

    private static func fragments(in image: UIImage) throws -> [OCRFragment] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" prices and odd menu names; keep raw text.
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation(of: image))
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return OCRFragment(text: text, box: observation.boundingBox)
        }
    }

    private static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
