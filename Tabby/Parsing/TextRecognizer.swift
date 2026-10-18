import UIKit
import Vision

/// On-device OCR using Apple's Vision framework. No network, no API keys.
///
/// Tries a few strategies (cleaned-up photo, iOS 26 document reader, raw
/// photo) and keeps whichever parse matches the receipt's own totals.
enum TextRecognizer {
    struct Scan {
        var receipt: ReceiptParser.Result
        /// The images the item anchors refer to, one per page.
        var pages: [CGImage]
    }

    static func read(_ images: [UIImage]) async throws -> Scan {
        try await Task.detached(priority: .userInitiated) { () async throws -> Scan in
            let pages = images.compactMap(ReceiptImageProcessor.variants(of:))
            var best: (scan: Scan, score: Int)?

            /// Records a candidate; returns it when it matches the receipt's totals.
            func consider(_ rows: [OCRRow], on images: [CGImage]) -> Scan? {
                guard !rows.isEmpty else { return nil }
                let scan = Scan(receipt: ReceiptParser.parse(ocrRows: rows), pages: images)
                let score = ReceiptParser.score(scan.receipt)
                if best == nil || score > best!.score {
                    best = (scan, score)
                }
                return scan.receipt.reconciles ? scan : nil
            }

            let enhanced = pages.map(\.enhanced)
            let display = pages.map(\.display)

            // 1. Cleaned-up photo, classic text recognizer.
            let classicRows = try enhanced.enumerated().flatMap { page, image in
                try TextRecognizer.lineRows(in: image, page: page)
            }
            if let done = consider(classicRows, on: display) { return done }

            // 2. iOS 26 document reader, which understands tables and rows.
            if #available(iOS 26.0, *) {
                var tableRows: [OCRRow] = []
                var lineRows: [OCRRow] = []
                for (page, image) in enhanced.enumerated() {
                    // Optional extra: if it fails, the other strategies still run.
                    guard let document = try? await TextRecognizer.documentRows(in: image, page: page) else { continue }
                    tableRows += document.tables
                    lineRows += document.lines
                }
                if let done = consider(tableRows, on: display) { return done }
                if let done = consider(lineRows, on: display) { return done }
            }

            // 3. The photo as taken.
            let originals = pages.map(\.original)
            let originalRows = try originals.enumerated().flatMap { page, image in
                try TextRecognizer.lineRows(in: image, page: page)
            }
            if let done = consider(originalRows, on: originals) { return done }

            return best?.scan ?? Scan(receipt: ReceiptParser.Result(), pages: display)
        }.value
    }

    // MARK: - Classic recognizer (iOS 17+)

    private static func lineRows(in image: CGImage, page: Int) throws -> [OCRRow] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" prices and odd menu names; keep raw text.
        request.usesLanguageCorrection = false
        // Receipts are long, so each line is a small fraction of the image.
        request.minimumTextHeight = 0.008
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        let size = CGSize(width: image.width, height: image.height)
        let fragments = (request.results ?? []).compactMap { observation -> OCRFragment? in
            let candidates = observation.topCandidates(3)
            guard let index = ReceiptParser.bestCandidateIndex(candidates.map(\.string)) else { return nil }
            let chosen = candidates[index]
            var fragment = OCRFragment(text: chosen.string,
                                       topLeft: pixel(observation.topLeft, size),
                                       topRight: pixel(observation.topRight, size),
                                       bottomLeft: pixel(observation.bottomLeft, size),
                                       bottomRight: pixel(observation.bottomRight, size))
            if let ranges = ReceiptParser.priceRanges(in: chosen.string) {
                fragment.priceRect = (try? chosen.boundingBox(for: ranges.price))
                    .map { pixel($0.boundingBox, size) }
                fragment.labelMaxX = ranges.label
                    .flatMap { try? chosen.boundingBox(for: $0) }
                    .map { pixel($0.boundingBox, size).maxX }
            }
            return fragment
        }
        return ReceiptParser.ocrRows(from: fragments, page: page)
    }

    // MARK: - Document reader (iOS 26+)

    @available(iOS 26.0, *)
    private static func documentRows(in image: CGImage, page: Int) async throws -> (tables: [OCRRow], lines: [OCRRow]) {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        request.textRecognitionOptions.maximumCandidateCount = 3
        request.textRecognitionOptions.minimumTextHeightFraction = 0.008
        let observations = try await request.perform(on: image, orientation: .up)
        guard let document = observations.first?.document else { return ([], []) }
        let size = CGSize(width: image.width, height: image.height)

        let tables = document.tables.flatMap { table in
            table.rows.map { row in
                let text = row.map { $0.content.text.transcript.replacingOccurrences(of: "\n", with: " ") }
                    .joined(separator: " ")
                let fragments = row.flatMap { $0.content.text.lines.map { fragment(from: $0, size: size) } }
                return OCRRow(text: text, anchor: ReceiptParser.anchor(for: fragments, page: page))
            }
        }
        let fragments = document.text.lines.map { fragment(from: $0, size: size) }
        return (tables, ReceiptParser.ocrRows(from: fragments, page: page))
    }

    @available(iOS 26.0, *)
    private static func fragment(from line: RecognizedTextObservation, size: CGSize) -> OCRFragment {
        let candidates = line.topCandidates(3)
        let chosen = ReceiptParser.bestCandidateIndex(candidates.map(\.string)).map { candidates[$0] }
        let text = chosen?.string ?? line.transcript
        var fragment = OCRFragment(text: text,
                                   topLeft: pixel(line.topLeft.cgPoint, size),
                                   topRight: pixel(line.topRight.cgPoint, size),
                                   bottomLeft: pixel(line.bottomLeft.cgPoint, size),
                                   bottomRight: pixel(line.bottomRight.cgPoint, size))
        if let chosen, let ranges = ReceiptParser.priceRanges(in: text) {
            fragment.priceRect = chosen.boundingBox(for: ranges.price)
                .map { pixel($0.boundingBox.cgRect, size) }
            fragment.labelMaxX = ranges.label
                .flatMap { chosen.boundingBox(for: $0) }
                .map { pixel($0.boundingBox.cgRect, size).maxX }
        }
        return fragment
    }

    // MARK: - Coordinates

    /// Vision's normalized coordinates (0...1, y up) to pixels (y up).
    private static func pixel(_ point: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private static func pixel(_ rect: CGRect, _ size: CGSize) -> CGRect {
        CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
               width: rect.width * size.width, height: rect.height * size.height)
    }
}
