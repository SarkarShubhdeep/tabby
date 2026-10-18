import CoreGraphics
import Foundation

/// A piece of recognized text. Corners are in pixel space with y pointing up
/// (Vision's normalized coordinates scaled by the image size).
struct OCRFragment: Equatable {
    var text: String
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint
    /// Where the trailing price sits, when this fragment contains one.
    var priceRect: CGRect?
    /// Right edge of the text before the price, when this fragment has any.
    var labelMaxX: CGFloat?

    init(text: String, topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) {
        self.text = text
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }

    /// An axis-aligned fragment.
    init(text: String, box: CGRect) {
        self.init(text: text,
                  topLeft: CGPoint(x: box.minX, y: box.maxY),
                  topRight: CGPoint(x: box.maxX, y: box.maxY),
                  bottomLeft: CGPoint(x: box.minX, y: box.minY),
                  bottomRight: CGPoint(x: box.maxX, y: box.minY))
    }

    var boundingRect: CGRect {
        let xs = [topLeft.x, topRight.x, bottomLeft.x, bottomRight.x]
        let ys = [topLeft.y, topRight.y, bottomLeft.y, bottomRight.y]
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    var center: CGPoint {
        CGPoint(x: (topLeft.x + topRight.x + bottomLeft.x + bottomRight.x) / 4,
                y: (topLeft.y + topRight.y + bottomLeft.y + bottomRight.y) / 4)
    }

    var width: CGFloat {
        (hypot(topRight.x - topLeft.x, topRight.y - topLeft.y)
            + hypot(bottomRight.x - bottomLeft.x, bottomRight.y - bottomLeft.y)) / 2
    }

    var height: CGFloat {
        (hypot(topLeft.x - bottomLeft.x, topLeft.y - bottomLeft.y)
            + hypot(topRight.x - bottomRight.x, topRight.y - bottomRight.y)) / 2
    }

    /// Rise over run of the text baseline.
    var slope: CGFloat? {
        let dx = (topRight.x - topLeft.x + bottomRight.x - bottomLeft.x) / 2
        let dy = (topRight.y - topLeft.y + bottomRight.y - bottomLeft.y) / 2
        return dx > 0 ? dy / dx : nil
    }
}

/// Where an item sits on the receipt image, in pixels with y pointing up.
struct ReceiptAnchor: Equatable {
    var page: Int
    var priceRect: CGRect
    /// Right edge of the item name, when known.
    var nameMaxX: CGFloat?
}

/// One visual line of the receipt.
struct OCRRow: Equatable {
    var text: String
    var anchor: ReceiptAnchor?
}

/// Turns OCR'd receipt text into line items. Anything it gets wrong is fixed
/// by the user on the Review screen.
enum ReceiptParser {
    struct Item: Equatable {
        var name: String
        var price: Decimal
        var anchor: ReceiptAnchor?
    }

    struct Result: Equatable {
        var items: [Item] = []
        var subtotal: Decimal?
        var tax: Decimal?
        var tip: Decimal?
        var total: Decimal?
        /// The text rows this result was parsed from, for troubleshooting.
        var rows: [String] = []

        var itemsSum: Decimal { items.reduce(0) { $0 + $1.price } }
        var extras: Decimal { (tax ?? 0) + (tip ?? 0) }

        /// True when the items add up to what the receipt itself says.
        var reconciles: Bool {
            if let total, abs(itemsSum + extras - total) <= 0.01 { return true }
            if let subtotal, abs(itemsSum - subtotal) <= 0.01 { return true }
            return false
        }
    }

    enum Kind: Equatable {
        case item, subtotal, tax, tip, discount, total, ignore
    }

    // MARK: - Rows

    /// Groups fragments into visual rows, top to bottom. Works on tilted
    /// photos by measuring the text angle and grouping along it, so a price
    /// at the far right still lands on the same row as its item name.
    static func rows(from fragments: [OCRFragment]) -> [String] {
        ocrRows(from: fragments, page: 0).map(\.text)
    }

    static func ocrRows(from fragments: [OCRFragment], page: Int) -> [OCRRow] {
        guard !fragments.isEmpty else { return [] }
        let slope = dominantSlope(of: fragments)
        let lineHeight = median(fragments.map(\.height).filter { $0 > 0 }) ?? 1

        // Position measured across the text lines, cancelling out the tilt.
        func level(_ fragment: OCRFragment) -> CGFloat {
            fragment.center.y - slope * fragment.center.x
        }
        func along(_ fragment: OCRFragment) -> CGFloat {
            fragment.center.x + slope * fragment.center.y
        }

        var rows: [(anchor: CGFloat, fragments: [OCRFragment])] = []
        for fragment in fragments.sorted(by: { level($0) > level($1) }) {
            let value = level(fragment)
            if let last = rows.last, last.anchor - value < lineHeight * 0.5 {
                rows[rows.count - 1].fragments.append(fragment)
            } else {
                rows.append((value, [fragment]))
            }
        }
        return rows.map { row in
            let sorted = row.fragments.sorted { along($0) < along($1) }
            return OCRRow(text: sorted.map(\.text).joined(separator: " "),
                          anchor: anchor(for: sorted, page: page))
        }
    }

    /// Locates a row's price and the end of its name, for annotating the image.
    /// `fragments` must be in reading order.
    static func anchor(for fragments: [OCRFragment], page: Int) -> ReceiptAnchor? {
        let fragments = fragments.map(withPriceGeometry)
        guard let index = fragments.lastIndex(where: { $0.priceRect != nil }),
              let priceRect = fragments[index].priceRect else { return nil }
        var nameMaxX = fragments[index].labelMaxX
        for fragment in fragments[..<index] where fragment.boundingRect.maxX <= priceRect.minX + 1 {
            nameMaxX = max(nameMaxX ?? fragment.boundingRect.maxX, fragment.boundingRect.maxX)
        }
        return ReceiptAnchor(page: page, priceRect: priceRect, nameMaxX: nameMaxX)
    }

    /// A fragment that is nothing but a price is its own price box.
    private static func withPriceGeometry(_ fragment: OCRFragment) -> OCRFragment {
        guard fragment.priceRect == nil, isPriceWithFlag(fragment.text) else { return fragment }
        var copy = fragment
        copy.priceRect = fragment.boundingRect
        return copy
    }

    /// Ranges of the trailing price and of the text before it, so the OCR
    /// layer can ask Vision exactly where each sits.
    static func priceRanges(in text: String) -> (label: Range<String.Index>?, price: Range<String.Index>)? {
        let fixed = fixMisreadPrice(text) as NSString   // same length as `text`
        guard let match = priceRegex.firstMatch(in: fixed as String, range: NSRange(location: 0, length: fixed.length)) else {
            return nil
        }
        func trimmed(_ range: NSRange) -> NSRange {
            var lower = range.location
            var upper = range.location + range.length
            func isSpace(_ unit: unichar) -> Bool {
                Unicode.Scalar(unit).map { CharacterSet.whitespaces.contains($0) } ?? false
            }
            while lower < upper, isSpace(fixed.character(at: lower)) { lower += 1 }
            while upper > lower, isSpace(fixed.character(at: upper - 1)) { upper -= 1 }
            return NSRange(location: lower, length: upper - lower)
        }
        guard let price = Range(trimmed(match.range), in: text) else { return nil }
        let labelRange = trimmed(NSRange(location: 0, length: match.range.location))
        let hasLetters = fixed.substring(with: labelRange).rangeOfCharacter(from: .letters) != nil
        let label = labelRange.length > 0 && hasLetters ? Range(labelRange, in: text) : nil
        return (label, price)
    }

    /// The text angle, from the fragments wide enough to measure it reliably.
    static func dominantSlope(of fragments: [OCRFragment]) -> CGFloat {
        let wide = fragments.filter { $0.width > $0.height * 2 }
        let slopes = (wide.isEmpty ? fragments : wide).compactMap(\.slope)
        let slope = median(slopes) ?? 0
        return min(max(slope, -0.5), 0.5)
    }

    /// Of several OCR readings of one fragment, prefers the most likely one
    /// that ends in a price, since a misread price is what hurts most.
    static func bestCandidate(_ candidates: [String]) -> String? {
        bestCandidateIndex(candidates).map { candidates[$0] }
    }

    static func bestCandidateIndex(_ candidates: [String]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        if splitPrice(candidates[0]) != nil { return 0 }
        return candidates.firstIndex { splitPrice($0) != nil } ?? 0
    }

    // MARK: - Parsing

    /// Parses each set of rows and keeps the result that best matches the
    /// receipt's own totals. Earlier candidates win ties.
    static func bestResult(from candidates: [[String]]) -> Result {
        var best: (result: Result, score: Int)?
        for rows in candidates {
            let result = parse(rows: rows)
            let value = score(result)
            if best == nil || value > best!.score {
                best = (result, value)
            }
        }
        return best?.result ?? Result()
    }

    static func score(_ result: Result) -> Int {
        (result.reconciles ? 10_000 : 0) + result.items.count
    }

    static func parse(rows: [String]) -> Result {
        parse(ocrRows: rows.map { OCRRow(text: $0, anchor: nil) })
    }

    static func parse(ocrRows: [OCRRow]) -> Result {
        var result = Result(rows: ocrRows.map(\.text))
        var discounts: [Item] = []
        for row in mergeOrphanPrices(ocrRows) {
            guard let line = splitPrice(row.text) else { continue }
            // Anything after the total is payment details, except a written-in tip.
            let afterTotal = result.total != nil
            switch classify(line.label) {
            case .item:
                if !afterTotal { result.items.append(Item(name: line.label, price: line.price, anchor: row.anchor)) }
            case .discount:
                if !afterTotal { discounts.append(Item(name: line.label, price: -abs(line.price), anchor: row.anchor)) }
            case .subtotal:
                if !afterTotal { result.subtotal = line.price }
            case .tax:
                if !afterTotal { result.tax = (result.tax ?? 0) + line.price }
            case .tip:
                result.tip = (result.tip ?? 0) + line.price
            case .total:
                if !afterTotal { result.total = line.price }
            case .ignore:
                break
            }
        }

        // Some receipts (e.g. Kroger) print savings that are already taken off
        // the item prices. Only subtract them if the totals say so.
        if !discounts.isEmpty, !result.reconciles {
            var withDiscounts = result
            withDiscounts.items += discounts
            if withDiscounts.reconciles || (result.total == nil && result.subtotal == nil) {
                result = withDiscounts
            }
        }
        return result
    }

    /// Splits "2 Burger  12.99" into ("2× Burger", 12.99). Returns nil when the
    /// row has no trailing price or no words.
    static func splitPrice(_ rawRow: String) -> (label: String, price: Decimal)? {
        let row = fixMisreadPrice(rawRow)
        let text = row as NSString
        guard let match = priceRegex.firstMatch(in: row, range: NSRange(location: 0, length: text.length)) else {
            return nil
        }
        let number = text.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: ".")
        guard var price = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        if match.range(at: 1).location != NSNotFound || match.range(at: 3).location != NSNotFound {
            price = -price
        }

        var label = text.substring(to: match.range.location)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".:$*#-")))
        label = formatQuantity(label)
        guard label.rangeOfCharacter(from: .letters) != nil else { return nil }
        return (label, price)
    }

    static func classify(_ label: String) -> Kind {
        if matches(label, subtotalRegex) { return .subtotal }
        if matches(label, taxRegex) { return .tax }
        if matches(label, tipRegex) { return .tip }
        if matches(label, discountRegex) { return .discount }
        if matches(label, ignoreRegex) { return .ignore }
        if matches(label, totalRegex) { return .total }
        return .item
    }

    // MARK: - Helpers

    /// When a price lands on its own row (tilted or wrapped layouts), joins it
    /// to the row above if that row is a name without a price.
    private static func mergeOrphanPrices(_ rows: [OCRRow]) -> [OCRRow] {
        var merged: [OCRRow] = []
        for row in rows {
            if isPriceWithFlag(row.text), let previous = merged.last,
               previous.text.rangeOfCharacter(from: .letters) != nil,
               splitPrice(previous.text) == nil {
                merged[merged.count - 1] = OCRRow(text: previous.text + " " + row.text, anchor: row.anchor)
            } else {
                merged.append(row)
            }
        }
        return merged
    }

    /// "4.19 F" or "S1.99": a price whose only letters are a currency or tax flag.
    private static func isPriceWithFlag(_ row: String) -> Bool {
        let text = row as NSString
        return priceOnlyRegex.firstMatch(in: row, range: NSRange(location: 0, length: text.length)) != nil
    }

    /// Fixes common OCR confusions inside the trailing price: O→0, l/I→1.
    private static func fixMisreadPrice(_ row: String) -> String {
        let text = row as NSString
        guard let match = misreadPriceRegex.firstMatch(in: row, range: NSRange(location: 0, length: text.length)) else {
            return row
        }
        let token = text.substring(with: match.range(at: 1))
        guard token.contains(where: \.isNumber) else { return row }
        let fixed = String(token.map { char -> Character in
            switch char {
            case "O", "o": return "0"
            case "l", "I": return "1"
            default: return char
            }
        })
        return text.replacingCharacters(in: match.range(at: 1), with: fixed)
    }

    /// "2 Burger" / "2x Burger" → "2× Burger"; "1 Burger" / "l Burger" → "Burger".
    private static func formatQuantity(_ label: String) -> String {
        let text = label as NSString
        guard let match = quantityRegex.firstMatch(in: label, range: NSRange(location: 0, length: text.length)) else {
            return label
        }
        let digits = text.substring(with: match.range(at: 1))
            .replacingOccurrences(of: "l", with: "1")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "|", with: "1")
        guard let quantity = Int(digits) else { return label }
        let name = text.substring(with: match.range(at: 2))
        return quantity > 1 ? "\(quantity)× \(name)" : name
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func matches(_ text: String, _ regex: NSRegularExpression) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static func regex(_ pattern: String, caseInsensitive: Bool = true) -> NSRegularExpression {
        // Patterns are constants; a bad one is a programmer error.
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    /// Trailing price: optional leading "-" or "$" (OCR often reads "$" as a
    /// lone "S"), digits with 2 decimals, optional trailing "-" (discount),
    /// optional tax flag like "T" or "F".
    private static let priceRegex = regex(
        #"(?:(-)\$?|(?:\$|(?<![A-Za-z])S)\s?)?(\d{1,5}[.,]\d{2})(-)?(?:\s*[A-Z]{1,2})?\s*$"#, caseInsensitive: false)
    private static let priceOnlyRegex = regex(
        #"^\s*(?:\$|S)?\s?-?\d{1,5}[.,]\d{2}-?(?:\s*[A-Z]{1,2})?\s*$"#, caseInsensitive: false)
    private static let misreadPriceRegex = regex(
        #"(?:^|[\s$S-])([0-9OoIl]{1,5}[.,][0-9OoIl]{2})-?(?:\s*[A-Z]{1,2})?\s*$"#, caseInsensitive: false)
    private static let quantityRegex = regex(#"^([0-9]{1,2}|[lI|])\s*[xX×@]?\s+(.*\p{L}.*)$"#, caseInsensitive: false)
    private static let subtotalRegex = regex(#"\bsub[\s-]?total\b|\bsubtl\b"#)
    private static let taxRegex = regex(#"\b(tax|taxes|vat|gst|hst|pst)\b"#)
    private static let tipRegex = regex(#"\b(tip|tips|gratuity|service charge)\b"#)
    private static let discountRegex = regex(#"\b(savings?|discount|coupon|promo)\b"#)
    private static let ignoreRegex = regex(
        #"\b(cash|change|visa|mastercard|amex|discover|card|credit|debit|payment|paid|tender|tendered|auth|approval|acct)\b"#)
    private static let totalRegex = regex(#"\b(total|amount due|balance due|balance|due)\b"#)
}
