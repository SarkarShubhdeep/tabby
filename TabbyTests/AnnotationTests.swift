import CoreGraphics
import UIKit
import XCTest
@testable import Tabby

final class AnnotationTests: XCTestCase {
    func testInitialsUseFirstLetterAndDisambiguateClashes() {
        XCTAssertEqual(BillSession.initials(for: ["Shubh", "Priyam"]), ["S", "P"])
        XCTAssertEqual(BillSession.initials(for: ["Sam", "Sara", "Bob"]), ["Sam", "Sar", "B"])
        XCTAssertEqual(BillSession.initials(for: ["shubh", "Sara"]), ["Sh", "Sa"])
        XCTAssertEqual(BillSession.initials(for: ["A", "B", " "]), ["A", "B", "?"])
    }

    func testPriceRanges() throws {
        let text = "Garlic pickle   $2.88 F"
        let ranges = try XCTUnwrap(ReceiptParser.priceRanges(in: text))
        XCTAssertEqual(String(text[ranges.price]), "$2.88 F")
        XCTAssertEqual(ranges.label.map { String(text[$0]) }, "Garlic pickle")

        let priceOnly = try XCTUnwrap(ReceiptParser.priceRanges(in: "4.O0"))
        XCTAssertNil(priceOnly.label)
        XCTAssertNil(ReceiptParser.priceRanges(in: "Kroger"))
    }

    func testRowsCarryItemPosition() throws {
        let name = OCRFragment(text: "Garlic pickle", box: CGRect(x: 50, y: 500, width: 260, height: 30))
        let price = OCRFragment(text: "2.88", box: CGRect(x: 600, y: 502, width: 80, height: 30))
        let total = OCRFragment(text: "Total 2.88", box: CGRect(x: 50, y: 400, width: 630, height: 30))
        let rows = ReceiptParser.ocrRows(from: [total, price, name], page: 0)
        XCTAssertEqual(rows.map(\.text), ["Garlic pickle 2.88", "Total 2.88"])

        let anchor = try XCTUnwrap(rows[0].anchor)
        XCTAssertEqual(anchor.priceRect, price.boundingRect)
        XCTAssertEqual(anchor.nameMaxX, 310)

        let result = ReceiptParser.parse(ocrRows: rows)
        XCTAssertEqual(result.items.first?.anchor, anchor)
    }

    func testRenderAddsLegendUnderReceipt() throws {
        let size = CGSize(width: 800, height: 1200)
        let page = try XCTUnwrap(UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }.cgImage)
        let anchor = ReceiptAnchor(page: 0, priceRect: CGRect(x: 600, y: 900, width: 80, height: 30), nameMaxX: 300)
        let image = try XCTUnwrap(ReceiptAnnotator.render(
            pages: [page],
            marks: [.init(anchor: anchor, people: [0, 1])],
            people: [.init(initial: "S", name: "Shubh", amount: "$1.44"),
                     .init(initial: "P", name: "Priyam", amount: "$1.44")],
            total: "$2.88"))
        XCTAssertGreaterThan(image.size.height, CGFloat(page.height))
    }

    func testSessionBuildsAnnotationFromScan() throws {
        let session = BillSession()
        session.addPerson(named: "Shubh")
        session.addPerson(named: "Priyam")
        let anchor = ReceiptAnchor(page: 0, priceRect: CGRect(x: 600, y: 900, width: 80, height: 30), nameMaxX: 300)
        session.items = [LineItem(name: "Garlic pickle", price: Decimal(string: "2.88")!,
                                  assignees: Set(session.people.map(\.id)), anchor: anchor)]
        XCTAssertNil(session.annotationJob(), "No scan, nothing to annotate")

        session.receiptPages = [try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600))
            .image { _ in }.cgImage)]
        let job = try XCTUnwrap(session.annotationJob())
        XCTAssertNotNil(job())
    }
}
