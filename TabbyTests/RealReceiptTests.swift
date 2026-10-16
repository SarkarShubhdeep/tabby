import CoreGraphics
import XCTest
@testable import Tabby

/// Fixtures transcribed from real receipts that failed in v1.
final class RealReceiptTests: XCTestCase {
    private func d(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    // MARK: - Kroger: dense rows, tax flags, savings already in item prices

    private let krogerRows = [
        "Kroger",
        "FRESH FOR EVERYONE",
        "1125 West State Blvd.",
        "260-426-3453 CHEC 510",
        "CHOC CROISSANT 5.49 F",
        "PS AL BTTR MNI CRO 5.00 F",
        "KROGER MILK 1.49 F",
        "FAIRLIFE MILK 5.49 F",
        "CLFM BLONDE ROAST 5.89 B",
        "COFFEEMATE CREAMER 4.19 F",
        "SC KROGER SAVINGS 0.30",
        "FAIRLIFE MILK 5.49 F",
        "FAIRLIFE MILK 5.49 F",
        "FAIRLIFE MILK 5.49 F",
        "CLFM COFFEE 5.89 B",
        "PRNG DPRS ORIG ET 2.39 F",
        "PFCHNG FRZN MEAL 8.49 F",
        "KRO PURIFIED WTR 4.00 F",
        "KRO PURIFIED WTR 4.00 F",
        "DIET PEPSI 11.99 T",
        "KROGER PLUS CUSTOMER *******5619",
        "TAX 1.66",
        "**** BALANCE 82.44",
        "Ft. Wayne IN 46808",
        "VISA CREDIT Purchase",
        "REF#: 012588 TOTAL: 82.44",
        "VISA 82.44",
        "CHANGE 0.00",
        "TOTAL NUMBER OF ITEMS SOLD = 15",
        "KROGER SAVINGS $ 0.30",
        "TOTAL SAVINGS (0 %) $ 0.30",
    ]

    func testKroger() {
        let result = ReceiptParser.parse(rows: krogerRows)
        XCTAssertEqual(result.items.count, 15)
        XCTAssertEqual(result.itemsSum, d("80.78"))
        XCTAssertEqual(result.tax, d("1.66"))
        XCTAssertEqual(result.total, d("82.44"))
        XCTAssertTrue(result.reconciles)
        XCTAssertFalse(result.items.contains { $0.name.contains("SAVINGS") },
                       "Savings are already in the item prices")
        XCTAssertEqual(result.items.first, .init(name: "CHOC CROISSANT", price: d("5.49")))
    }

    // MARK: - Almadenah: faded print, "$" read as "S", "1" read as "l"

    private let almadenahItems: [(String, String, String)] = [
        ("1", "Poha", "$2.99"), ("1", "Res Rusk", "$3.99"), ("l", "Red Label Tea", "S7.99"),
        ("1", "Peanut 200g", "$1.99"), ("1", "Custom Item", "$0.50"), ("3", "Custom Item", "$1.49"),
        ("1", "Homemeal Parat", "$9.99"), ("2", "Roti", "$7.98"), ("1", "Custom Item", "S1.77"),
        ("1", "Custom Item", "$2.99"), ("1", "Chilli", "$1.69"), ("1", "Toblerone Dark Chocolate", "$2.49"),
        ("1", "Custom Item", "$6.52"), ("I", "Custom Item", "$6.70"),
    ]

    func testAlmadenahRows() {
        var rows = ["ALMADENAH HALAL MEAT MAR", "12-Oct-2026 9:17:47P", "Transaction 010700"]
        rows += almadenahItems.map { "\($0.0) \($0.1) \($0.2)" }
        rows += ["Total $59.08", "CREDIT CARD SALE $59.08", "DISCOVER 3932"]

        let result = ReceiptParser.parse(rows: rows)
        XCTAssertEqual(result.items.count, 14)
        XCTAssertEqual(result.total, d("59.08"))
        XCTAssertTrue(result.reconciles)
        XCTAssertEqual(result.items[0].name, "Poha")
        XCTAssertEqual(result.items[2].name, "Red Label Tea")
        XCTAssertEqual(result.items[5].name, "3× Custom Item")
        XCTAssertEqual(result.items[7], .init(name: "2× Roti", price: d("7.98")))
        XCTAssertEqual(result.items[13].name, "Custom Item")
    }

    /// The photo was taken at an angle: each price sits closer to the next
    /// item's name than to its own. Tilt-aware grouping must still pair them.
    func testAlmadenahTiltedPhoto() {
        let slope: CGFloat = -0.057   // right side lower (y points up)
        func fragment(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> OCRFragment {
            let height: CGFloat = 30
            return OCRFragment(text: text,
                               topLeft: CGPoint(x: x, y: y + height),
                               topRight: CGPoint(x: x + width, y: y + height + slope * width),
                               bottomLeft: CGPoint(x: x, y: y),
                               bottomRight: CGPoint(x: x + width, y: y + slope * width))
        }
        // Where a point at horizontal position `x` on the line starting at (60, y) ends up.
        func lineY(_ y: CGFloat, at x: CGFloat) -> CGFloat { y + slope * (x - 60) }

        var fragments = [fragment("ALMADENAH HALAL MEAT MAR", x: 60, y: 1800, width: 700)]
        var y: CGFloat = 1600
        for (quantity, name, price) in almadenahItems {
            fragments.append(fragment(quantity, x: 60, y: y, width: 20))
            fragments.append(fragment(name, x: 130, y: lineY(y, at: 130), width: CGFloat(name.count) * 18))
            fragments.append(fragment(price, x: 700, y: lineY(y, at: 700), width: 80))
            y -= 45
        }
        fragments.append(fragment("Total", x: 60, y: y, width: 90))
        fragments.append(fragment("$59.08", x: 680, y: lineY(y, at: 680), width: 100))
        fragments.shuffle()

        let rows = ReceiptParser.rows(from: fragments)
        XCTAssertTrue(rows.contains("1 Poha $2.99"), "\(rows)")
        XCTAssertTrue(rows.contains("2 Roti $7.98"), "\(rows)")

        let result = ReceiptParser.parse(rows: rows)
        XCTAssertEqual(result.items.count, 14)
        XCTAssertTrue(result.reconciles)
    }

    // MARK: - Smaller fixes

    func testPriceOnItsOwnRowJoinsNameAbove() {
        let result = ReceiptParser.parse(rows: ["1 Poha", "$2.99", "1 Res Rusk", "S3.99", "Total $6.98"])
        XCTAssertEqual(result.items, [.init(name: "Poha", price: d("2.99")),
                                      .init(name: "Res Rusk", price: d("3.99"))])
    }

    func testMisreadDigitsInPrice() {
        XCTAssertEqual(ReceiptParser.splitPrice("Fries 4.O0")?.price, d("4.00"))
        XCTAssertEqual(ReceiptParser.splitPrice("Tea l.99")?.price, d("1.99"))
        XCTAssertEqual(ReceiptParser.splitPrice("Milk 5.49F")?.price, d("5.49"))
        XCTAssertEqual(ReceiptParser.splitPrice("Chips S1.69")?.label, "Chips")
        XCTAssertEqual(ReceiptParser.splitPrice("FRIES 3.99")?.label, "FRIES")
    }

    func testBestCandidatePrefersOneWithPrice() {
        XCTAssertEqual(ReceiptParser.bestCandidate(["Poha $2.g9", "Poha $2.99"]), "Poha $2.99")
        XCTAssertEqual(ReceiptParser.bestCandidate(["Kroger", "Kr0ger"]), "Kroger")
        XCTAssertNil(ReceiptParser.bestCandidate([]))
    }

    func testDiscountSubtractedWhenTotalsSaySo() {
        let rows = ["Pizza 20.00", "Coupon 5.00", "Total 15.00"]
        let result = ReceiptParser.parse(rows: rows)
        XCTAssertEqual(result.items.last, .init(name: "Coupon", price: d("-5.00")))
        XCTAssertTrue(result.reconciles)
    }

    func testBestResultPicksReconcilingCandidate() {
        let misgrouped = ["1 Poha", "1 Res Rusk $2.99", "Total $6.98 $3.99"]
        let correct = ["1 Poha $2.99", "1 Res Rusk $3.99", "Total $6.98"]
        let result = ReceiptParser.bestResult(from: [misgrouped, correct])
        XCTAssertEqual(result.rows, correct)
    }
}
