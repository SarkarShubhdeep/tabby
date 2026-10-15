import CoreGraphics
import Foundation

/// A piece of recognized text. `box` uses Vision's normalized coordinates
/// (origin bottom-left, 0...1).
struct OCRFragment: Equatable {
    var text: String
    var box: CGRect
}

/// Turns OCR'd receipt text into line items. Deliberately simple: anything
/// it gets wrong is fixed by the user on the Review screen.
enum ReceiptParser {
    struct Item: Equatable {
        var name: String
        var price: Decimal
    }

    struct Result: Equatable {
        var items: [Item] = []
        var subtotal: Decimal?
        var tax: Decimal?
        var tip: Decimal?
        var total: Decimal?
    }

    enum Kind: Equatable {
        case item, subtotal, tax, tip, total, ignore
    }

    // MARK: - Rows

    /// Groups fragments into visual rows, top to bottom. Receipts often put the
    /// item name and its price in separate fragments on the same line.
    static func rows(from fragments: [OCRFragment]) -> [String] {
        let sorted = fragments.sorted { $0.box.midY > $1.box.midY }
        var rows: [[OCRFragment]] = []
        for fragment in sorted {
            if let anchor = rows.last?.first,
               abs(anchor.box.midY - fragment.box.midY) < min(anchor.box.height, fragment.box.height) * 0.5 {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
        }
    }

    // MARK: - Parsing

    static func parse(rows: [String]) -> Result {
        var result = Result()
        for row in rows {
            guard let line = splitPrice(row) else { continue }
            switch classify(line.label) {
            case .item:
                // Anything after the total is payment details, not food.
                if result.total == nil {
                    result.items.append(Item(name: line.label, price: line.price))
                }
            case .subtotal:
                result.subtotal = line.price
            case .tax:
                result.tax = (result.tax ?? 0) + line.price
            case .tip:
                result.tip = (result.tip ?? 0) + line.price
            case .total:
                if result.total == nil { result.total = line.price }
            case .ignore:
                break
            }
        }
        return result
    }

    /// Splits "2 Burger  12.99" into ("2× Burger", 12.99). Returns nil when the
    /// row has no trailing price or no words.
    static func splitPrice(_ row: String) -> (label: String, price: Decimal)? {
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
        if matches(label, ignoreRegex) { return .ignore }
        if matches(label, totalRegex) { return .total }
        return .item
    }

    // MARK: - Helpers

    /// "2 Burger" / "2x Burger" → "2× Burger"; "1 Burger" → "Burger".
    private static func formatQuantity(_ label: String) -> String {
        let text = label as NSString
        guard let match = quantityRegex.firstMatch(in: label, range: NSRange(location: 0, length: text.length)),
              let quantity = Int(text.substring(with: match.range(at: 1)))
        else { return label }
        let name = text.substring(with: match.range(at: 2))
        return quantity > 1 ? "\(quantity)× \(name)" : name
    }

    private static func matches(_ text: String, _ regex: NSRegularExpression) -> Bool {
        regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static func regex(_ pattern: String, caseInsensitive: Bool = true) -> NSRegularExpression {
        // Patterns are constants; a bad one is a programmer error.
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    /// Trailing price: optional leading "-" or "$", digits with 2 decimals,
    /// optional trailing "-" (discount), optional tax flag like "T" or "N".
    private static let priceRegex = regex(
        #"(?:(-)\$?|\$\s?)?(\d{1,5}[.,]\d{2})(-)?(?:\s+[A-Z]{1,2})?\s*$"#, caseInsensitive: false)
    private static let quantityRegex = regex(#"^(\d{1,2})\s*[x×@]?\s+(.*\p{L}.*)$"#)
    private static let subtotalRegex = regex(#"\bsub[\s-]?total\b|\bsubtl\b"#)
    private static let taxRegex = regex(#"\b(tax|taxes|vat|gst|hst|pst)\b"#)
    private static let tipRegex = regex(#"\b(tip|tips|gratuity|service charge)\b"#)
    private static let ignoreRegex = regex(
        #"\b(cash|change|visa|mastercard|amex|discover|card|credit|debit|payment|paid|tender|tendered|auth|approval|acct)\b"#)
    private static let totalRegex = regex(#"\b(total|amount due|balance due|balance|due)\b"#)
}
