import UIKit

/// Draws who-had-what onto the scanned receipt: each item gets its people's
/// initials between the name and the price, and a legend lists everyone's share.
enum ReceiptAnnotator {
    struct Mark {
        var anchor: ReceiptAnchor
        /// Indexes into `people`.
        var people: [Int]
    }

    struct Person {
        var initial: String
        var name: String
        var amount: String
    }

    static let palette: [UIColor] = [
        .systemOrange, .systemBlue, .systemGreen, .systemPink, .systemPurple,
        .systemTeal, .systemIndigo, .systemRed, .systemBrown, .systemMint,
    ]

    static func color(for index: Int) -> UIColor {
        palette[index % palette.count]
    }

    static func render(pages: [CGImage], marks: [Mark], people: [Person], total: String) -> UIImage? {
        guard !pages.isEmpty else { return nil }
        let pageWidth = CGFloat(pages.map(\.width).max() ?? 0)
        let unit = pageWidth / 100   // everything scales with the receipt

        // Badge layout per mark, in page pixels (top-left origin).
        struct Placement { var page: Int; var frame: CGRect; var people: [Int] }
        var placements: [Placement] = []
        var marginWidth: CGFloat = 0
        for mark in marks where mark.anchor.page < pages.count && !mark.people.isEmpty {
            let page = pages[mark.anchor.page]
            let price = mark.anchor.priceRect
            let diameter = max(price.height * 1.15, unit * 2.4)
            let spacing = diameter * 0.15
            let width = CGFloat(mark.people.count) * diameter + CGFloat(mark.people.count - 1) * spacing
            let top = CGFloat(page.height) - price.maxY + (price.height - diameter) / 2

            let x: CGFloat
            if let nameMaxX = mark.anchor.nameMaxX, price.minX - nameMaxX >= width + diameter * 0.6 {
                x = nameMaxX + (price.minX - nameMaxX - width) / 2
            } else {
                // No room between name and price: use a margin to the right of the receipt.
                x = CGFloat(page.width) + unit * 2
                marginWidth = max(marginWidth, width + unit * 4)
            }
            placements.append(Placement(page: mark.anchor.page,
                                        frame: CGRect(x: x, y: top, width: width, height: diameter),
                                        people: mark.people))
        }

        // Legend under the receipt.
        let legendFont = UIFont.systemFont(ofSize: unit * 4.2, weight: .semibold)
        let lineHeight = legendFont.lineHeight * 1.5
        let legendHeight = lineHeight * CGFloat(people.count + 1) + unit * 8

        let canvasWidth = pageWidth + marginWidth
        var pageOffsets: [CGFloat] = []
        var pagesHeight: CGFloat = 0
        for page in pages {
            pageOffsets.append(pagesHeight)
            pagesHeight += CGFloat(page.height)
        }
        let canvas = CGSize(width: canvasWidth, height: pagesHeight + legendHeight)

        // Keep the shared image a reasonable size.
        let scale = min(1, 2000 / canvas.width, 8000 / canvas.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvas.width * scale,
                                                            height: canvas.height * scale),
                                               format: format)
        return renderer.image { context in
            context.cgContext.scaleBy(x: scale, y: scale)
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))

            for (index, page) in pages.enumerated() {
                UIImage(cgImage: page).draw(in: CGRect(x: 0, y: pageOffsets[index],
                                                       width: CGFloat(page.width),
                                                       height: CGFloat(page.height)))
            }

            for placement in placements {
                var x = placement.frame.minX
                let y = placement.frame.minY + pageOffsets[placement.page]
                let diameter = placement.frame.height
                for person in placement.people {
                    drawBadge(people.indices.contains(person) ? people[person].initial : "?",
                              color: color(for: person),
                              in: CGRect(x: x, y: y, width: diameter, height: diameter))
                    x += diameter * 1.15
                }
            }

            // Legend.
            var y = pagesHeight + unit * 4
            let left = unit * 6
            let right = pageWidth - unit * 6
            let diameter = legendFont.lineHeight
            for (index, person) in people.enumerated() {
                drawBadge(person.initial, color: color(for: index),
                          in: CGRect(x: left, y: y + (lineHeight - diameter) / 2, width: diameter, height: diameter))
                drawText(person.name, font: legendFont, at: CGPoint(x: left + diameter * 1.5, y: y),
                         lineHeight: lineHeight)
                drawText(person.amount, font: legendFont, rightAlignedTo: right, y: y, lineHeight: lineHeight)
                y += lineHeight
            }
            let totalFont = UIFont.systemFont(ofSize: unit * 4.2, weight: .heavy)
            drawText("Total", font: totalFont, at: CGPoint(x: left, y: y), lineHeight: lineHeight)
            drawText(total, font: totalFont, rightAlignedTo: right, y: y, lineHeight: lineHeight)
        }
    }

    private static func drawBadge(_ text: String, color: UIColor, in rect: CGRect) {
        color.setFill()
        UIBezierPath(ovalIn: rect).fill()
        let font = UIFont.systemFont(ofSize: rect.height * (text.count > 1 ? 0.45 : 0.6), weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                                withAttributes: attributes)
    }

    private static func drawText(_ text: String, font: UIFont, at point: CGPoint, lineHeight: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        (text as NSString).draw(at: CGPoint(x: point.x, y: point.y + (lineHeight - font.lineHeight) / 2),
                                withAttributes: attributes)
    }

    private static func drawText(_ text: String, font: UIFont, rightAlignedTo right: CGFloat, y: CGFloat,
                                 lineHeight: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let width = (text as NSString).size(withAttributes: attributes).width
        drawText(text, font: font, at: CGPoint(x: right - width, y: y), lineHeight: lineHeight)
    }
}

extension BillSession {
    /// Everything the annotator needs, captured on the main thread so the
    /// drawing itself can happen in the background.
    func annotationJob() -> (() -> UIImage?)? {
        guard !receiptPages.isEmpty else { return nil }
        let pages = receiptPages
        let marks = items.compactMap { item -> ReceiptAnnotator.Mark? in
            guard let anchor = item.anchor else { return nil }
            let owners = people.indices.filter { item.assignees.contains(people[$0].id) }
            return ReceiptAnnotator.Mark(anchor: anchor, people: owners)
        }
        let initials = self.initials
        let shares = shares()
        let people = shares.indices.map { index in
            ReceiptAnnotator.Person(initial: initials[index],
                                    name: shares[index].person.name,
                                    amount: Money.format(shares[index].total))
        }
        let total = Money.format(self.total)
        return { ReceiptAnnotator.render(pages: pages, marks: marks, people: people, total: total) }
    }
}
