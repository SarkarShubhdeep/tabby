import Foundation

enum Money {
    static var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    static func format(_ value: Decimal) -> String {
        value.formatted(.currency(code: currencyCode))
    }

    /// Rounds to whole cents (half away from zero).
    static func cents(_ value: Decimal) -> Int {
        var input = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    static func decimal(cents: Int) -> Decimal {
        Decimal(cents) / 100
    }
}
