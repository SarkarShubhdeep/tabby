import CoreGraphics
import XCTest
@testable import Tabby

final class ReceiptParserTests: XCTestCase {
    private func d(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    func testParsesItemsTaxTipAndTotal() {
        let rows = [
            "JOE'S DINER",
            "123 Main St",
            "2 Burger 25.98",
            "Fries 4.50",
            "Coke $2.00",
            "Subtotal 32.48",
            "Sales Tax 2.60",
            "Tip 5.00",
            "Total 40.08",
            "Visa 40.08",
        ]
        let result = ReceiptParser.parse(rows: rows)
        XCTAssertEqual(result.items, [
            .init(name: "2× Burger", price: d("25.98")),
            .init(name: "Fries", price: d("4.50")),
            .init(name: "Coke", price: d("2.00")),
        ])
        XCTAssertEqual(result.subtotal, d("32.48"))
        XCTAssertEqual(result.tax, d("2.60"))
        XCTAssertEqual(result.tip, d("5.00"))
        XCTAssertEqual(result.total, d("40.08"))
    }

    func testIgnoresRowsAfterTotal() {
        let rows = ["Pasta 14.00", "Total 14.00", "Cash 20.00", "Change 6.00", "Thank you 1.00"]
        XCTAssertEqual(ReceiptParser.parse(rows: rows).items.map(\.name), ["Pasta"])
    }

    func testPriceFormats() {
        XCTAssertEqual(ReceiptParser.splitPrice("Fries - 3.99")?.price, d("3.99"))
        XCTAssertEqual(ReceiptParser.splitPrice("Fries - 3.99")?.label, "Fries")
        XCTAssertEqual(ReceiptParser.splitPrice("Happy hour -2.00")?.price, d("-2.00"))
        XCTAssertEqual(ReceiptParser.splitPrice("Coupon 1.50-")?.price, d("-1.50"))
        XCTAssertEqual(ReceiptParser.splitPrice("Milk 3,49")?.price, d("3.49"))
        XCTAssertEqual(ReceiptParser.splitPrice("Bread 2.99 T")?.price, d("2.99"))
        XCTAssertEqual(ReceiptParser.splitPrice("1 Salad 9.00")?.label, "Salad")
        XCTAssertNil(ReceiptParser.splitPrice("Table 12"))
        XCTAssertNil(ReceiptParser.splitPrice("12/10/2026 19.30"))
    }

    func testClassify() {
        XCTAssertEqual(ReceiptParser.classify("SUB-TOTAL"), .subtotal)
        XCTAssertEqual(ReceiptParser.classify("VAT 20%"), .tax)
        XCTAssertEqual(ReceiptParser.classify("Gratuity"), .tip)
        XCTAssertEqual(ReceiptParser.classify("Amount Due"), .total)
        XCTAssertEqual(ReceiptParser.classify("Mastercard"), .ignore)
        XCTAssertEqual(ReceiptParser.classify("Cashew Chicken"), .item)
        XCTAssertEqual(ReceiptParser.classify("Fondue"), .item)
    }

    func testGroupsFragmentsIntoRows() {
        let fragments = [
            OCRFragment(text: "4.50", box: CGRect(x: 0.8, y: 0.70, width: 0.1, height: 0.03)),
            OCRFragment(text: "Burger", box: CGRect(x: 0.1, y: 0.80, width: 0.3, height: 0.03)),
            OCRFragment(text: "Fries", box: CGRect(x: 0.1, y: 0.705, width: 0.2, height: 0.03)),
            OCRFragment(text: "12.00", box: CGRect(x: 0.8, y: 0.795, width: 0.1, height: 0.03)),
        ]
        XCTAssertEqual(ReceiptParser.rows(from: fragments), ["Burger 12.00", "Fries 4.50"])
    }
}
