import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// Cleans up a receipt photo before OCR: finds the receipt, straightens it,
/// enlarges small text and boosts faded print.
enum ReceiptImageProcessor {
    private static let context = CIContext()

    struct Variants {
        /// Cropped, straightened, enlarged and enhanced. Best for most photos.
        var enhanced: CGImage
        /// The same crop in color, for showing and annotating. Same geometry as `enhanced`.
        var display: CGImage
        /// The photo as taken, as a fallback when cleanup makes things worse.
        var original: CGImage
    }

    static func variants(of image: UIImage) -> Variants? {
        guard let base = orientedImage(image) else { return nil }
        let receipt = upscaled(straightened(base) ?? base)
        guard let enhanced = render(enhance(receipt)),
              let display = render(receipt),
              let original = render(base) else { return nil }
        return Variants(enhanced: enhanced, display: display, original: original)
    }

    // MARK: - Steps

    private static func orientedImage(_ image: UIImage) -> CIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let oriented = CIImage(cgImage: cgImage).oriented(orientation(of: image))
        return oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX,
                                                          y: -oriented.extent.minY))
    }

    /// Finds the receipt's edges and flattens it to a straight rectangle.
    private static func straightened(_ image: CIImage) -> CIImage? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try? handler.perform([request])
        guard let quad = request.results?.first, quad.confidence > 0.5 else { return nil }

        let size = image.extent.size
        func point(_ normalized: CGPoint) -> CGPoint {
            CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
        }
        // Ignore implausibly small detections (a label, a logo).
        let box = quad.boundingBox
        guard box.width * box.height > 0.05 else { return nil }

        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = image
        filter.topLeft = point(quad.topLeft)
        filter.topRight = point(quad.topRight)
        filter.bottomLeft = point(quad.bottomLeft)
        filter.bottomRight = point(quad.bottomRight)
        guard let output = filter.outputImage else { return nil }
        return output.transformed(by: CGAffineTransform(translationX: -output.extent.minX,
                                                        y: -output.extent.minY))
    }

    /// Small, far-away receipts read much better when enlarged.
    private static func upscaled(_ image: CIImage) -> CIImage {
        let size = image.extent.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(3, 1600 / size.width, 4096 / max(size.width, size.height))
        guard scale > 1.1 else { return image }
        let filter = CIFilter.lanczosScaleTransform()
        filter.inputImage = image
        filter.scale = Float(scale)
        filter.aspectRatio = 1
        return filter.outputImage ?? image
    }

    /// Whitens the paper, removes shadows and darkens faded thermal print.
    private static func enhance(_ image: CIImage) -> CIImage {
        let document = CIFilter.documentEnhancer()
        document.inputImage = image
        document.amount = 1

        let mono = CIFilter.colorControls()
        mono.inputImage = document.outputImage ?? image
        mono.saturation = 0
        mono.contrast = 1.15

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = mono.outputImage
        sharpen.sharpness = 0.4
        return sharpen.outputImage ?? image
    }

    private static func render(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent.integral)
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
