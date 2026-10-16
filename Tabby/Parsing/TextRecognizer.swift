import UIKit
import Vision

/// On-device OCR using Apple's Vision framework. No network, no API keys.
///
/// Tries a few strategies (cleaned-up photo, iOS 26 document reader, raw
/// photo) and keeps whichever parse matches the receipt's own totals.
enum TextRecognizer {
    static func read(_ images: [UIImage]) async throws -> ReceiptParser.Result {
        try await Task.detached(priority: .userInitiated) { () async throws -> ReceiptParser.Result in
            let pages = images.map(ReceiptImageProcessor.variants(of:))
            var candidates: [[String]] = []

            func tryCandidate(_ rows: [String]) -> ReceiptParser.Result? {
                guard !rows.isEmpty else { return nil }
                candidates.append(rows)
                let result = ReceiptParser.parse(rows: rows)
                return result.reconciles ? result : nil
            }

            // 1. Cleaned-up photo, classic text recognizer.
            let enhanced = pages.compactMap(\.enhanced)
            if let done = tryCandidate(try enhanced.flatMap(TextRecognizer.lineRows(in:))) {
                return done
            }

            // 2. iOS 26 document reader, which understands tables and rows.
            if #available(iOS 26.0, *) {
                var tableRows: [String] = []
                var lineRows: [String] = []
                for image in enhanced {
                    let document = try await TextRecognizer.documentRows(in: image)
                    tableRows += document.tables
                    lineRows += document.lines
                }
                if let done = tryCandidate(tableRows) { return done }
                if let done = tryCandidate(lineRows) { return done }
            }

            // 3. The photo as taken.
            let originals = pages.compactMap(\.original)
            if let done = tryCandidate(try originals.flatMap(TextRecognizer.lineRows(in:))) {
                return done
            }

            return ReceiptParser.bestResult(from: candidates)
        }.value
    }

    // MARK: - Classic recognizer (iOS 17+)

    private static func lineRows(in image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" prices and odd menu names; keep raw text.
        request.usesLanguageCorrection = false
        // Receipts are long, so each line is a small fraction of the image.
        request.minimumTextHeight = 0.008
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        let size = CGSize(width: image.width, height: image.height)
        func pixel(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * size.width, y: point.y * size.height)
        }
        let fragments = (request.results ?? []).compactMap { observation -> OCRFragment? in
            let candidates = observation.topCandidates(3).map(\.string)
            guard let text = ReceiptParser.bestCandidate(candidates) else { return nil }
            return OCRFragment(text: text,
                               topLeft: pixel(observation.topLeft),
                               topRight: pixel(observation.topRight),
                               bottomLeft: pixel(observation.bottomLeft),
                               bottomRight: pixel(observation.bottomRight))
        }
        return ReceiptParser.rows(from: fragments)
    }

    // MARK: - Document reader (iOS 26+)

    @available(iOS 26.0, *)
    private static func documentRows(in image: CGImage) async throws -> (tables: [String], lines: [String]) {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        request.textRecognitionOptions.maximumCandidateCount = 3
        request.textRecognitionOptions.minimumTextHeightFraction = 0.008
        let observations = try await request.perform(on: image, orientation: .up)
        guard let document = observations.first?.document else { return ([], []) }

        let tables = document.tables.flatMap { table in
            table.rows.map { row in
                row.map { $0.content.text.transcript.replacingOccurrences(of: "\n", with: " ") }
                    .joined(separator: " ")
            }
        }

        let size = CGSize(width: image.width, height: image.height)
        func pixel(_ point: NormalizedPoint) -> CGPoint {
            CGPoint(x: point.x * size.width, y: point.y * size.height)
        }
        let fragments = document.text.lines.map { line in
            let text = ReceiptParser.bestCandidate(line.topCandidates(3).map(\.string)) ?? line.transcript
            return OCRFragment(text: text,
                               topLeft: pixel(line.topLeft),
                               topRight: pixel(line.topRight),
                               bottomLeft: pixel(line.bottomLeft),
                               bottomRight: pixel(line.bottomRight))
        }
        return (tables, ReceiptParser.rows(from: fragments))
    }
}
