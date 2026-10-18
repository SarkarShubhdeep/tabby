import CoreGraphics
import Foundation
import Observation

struct Person: Identifiable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct LineItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var price: Decimal
    var assignees: Set<UUID>
    /// Where this item is on the scanned receipt, if it came from a scan.
    var anchor: ReceiptAnchor?

    init(id: UUID = UUID(), name: String, price: Decimal, assignees: Set<UUID> = [], anchor: ReceiptAnchor? = nil) {
        self.id = id
        self.name = name
        self.price = price
        self.assignees = assignees
        self.anchor = anchor
    }
}

struct PersonShare: Identifiable {
    struct Entry: Identifiable {
        let id = UUID()
        let name: String
        let amount: Decimal
        let splitCount: Int
    }

    let person: Person
    let entries: [Entry]
    let subtotal: Decimal
    let extras: Decimal

    var id: UUID { person.id }
    var total: Decimal { subtotal + extras }
}

@Observable
final class BillSession {
    var items: [LineItem] = []
    var people: [Person] = []
    var tax: Decimal = 0
    var tip: Decimal = 0
    /// Subtotal and total printed on the receipt, used to warn about misread lines.
    var receiptSubtotal: Decimal?
    var receiptTotal: Decimal?
    /// The text rows OCR produced, for troubleshooting.
    var recognizedRows: [String] = []
    /// The scanned receipt, one image per page, for the annotated copy.
    var receiptPages: [CGImage] = []

    var itemsSubtotal: Decimal { items.reduce(0) { $0 + $1.price } }
    var total: Decimal { itemsSubtotal + tax + tip }

    var unassignedItems: [LineItem] {
        items.filter { item in !people.contains { item.assignees.contains($0.id) } }
    }

    /// Letter used to pick a person on the assign screen: A, B, C…
    static func keyLetter(for offset: Int) -> String {
        guard (0..<26).contains(offset), let scalar = UnicodeScalar(65 + offset) else { return "" }
        return String(Character(scalar))
    }

    // MARK: - Bill

    /// Clears the bill but keeps the people, since groups usually stay the same.
    func startNewBill() {
        items = []
        tax = 0
        tip = 0
        receiptSubtotal = nil
        receiptTotal = nil
        recognizedRows = []
        receiptPages = []
    }

    func load(_ scan: TextRecognizer.Scan) {
        load(scan.receipt)
        receiptPages = scan.pages
    }

    func load(_ result: ReceiptParser.Result) {
        items = result.items.map { LineItem(name: $0.name, price: $0.price, anchor: $0.anchor) }
        tax = result.tax ?? 0
        tip = result.tip ?? 0
        receiptSubtotal = result.subtotal
        receiptTotal = result.total
        recognizedRows = result.rows
    }

    /// Explains how the items disagree with the receipt's printed totals, if they do.
    var mismatchWarning: String? {
        if let receipt = receiptSubtotal, receipt != itemsSubtotal {
            return "Items add up to \(Money.format(itemsSubtotal)), but the receipt's subtotal is \(Money.format(receipt)). Check for missed or misread lines."
        }
        if receiptSubtotal == nil, let receipt = receiptTotal, receipt != total {
            return "This adds up to \(Money.format(total)), but the receipt's total is \(Money.format(receipt)). Check for missed or misread lines."
        }
        return nil
    }

    // MARK: - People

    @discardableResult
    func addPerson(named raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !people.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { return false }
        people.append(Person(name: name))
        return true
    }

    func removePeople(at offsets: IndexSet) {
        let removed = Set(offsets.map { people[$0].id })
        people.removeAll { removed.contains($0.id) }
        for index in items.indices {
            items[index].assignees.subtract(removed)
        }
    }

    /// Gives anyone whose name was cleared their letter back.
    func normalizePeopleNames() {
        for index in people.indices {
            let trimmed = people[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
            people[index].name = trimmed.isEmpty ? Self.keyLetter(for: index) : trimmed
        }
    }

    // MARK: - Shares

    /// Each person's share. Shared items are split evenly; tax and tip are split
    /// in proportion to each person's subtotal. All math is done in whole cents so
    /// the shares always add up exactly.
    func shares() -> [PersonShare] {
        var subtotals = Array(repeating: 0, count: people.count)
        var entries = Array(repeating: [PersonShare.Entry](), count: people.count)

        for item in items {
            let owners = people.indices.filter { item.assignees.contains(people[$0].id) }
            guard !owners.isEmpty else { continue }
            let parts = Self.split(Money.cents(item.price), into: owners.count)
            for (owner, part) in zip(owners, parts) {
                subtotals[owner] += part
                entries[owner].append(.init(name: item.name,
                                            amount: Money.decimal(cents: part),
                                            splitCount: owners.count))
            }
        }

        let extras = Self.distribute(Money.cents(tax + tip), weights: subtotals)
        return people.indices.map { index in
            PersonShare(person: people[index],
                        entries: entries[index],
                        subtotal: Money.decimal(cents: subtotals[index]),
                        extras: Money.decimal(cents: extras[index]))
        }
    }

    /// Short labels for the annotated receipt: first letter of each name,
    /// with more letters only where two people would otherwise clash.
    static func initials(for names: [String]) -> [String] {
        let trimmed = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        func label(_ name: String, length: Int) -> String {
            guard !name.isEmpty else { return "?" }
            let prefix = name.prefix(length)
            return prefix.prefix(1).uppercased() + prefix.dropFirst().lowercased()
        }
        var result = trimmed.map { label($0, length: 1) }
        for length in 2...4 {
            let groups = Dictionary(grouping: result.indices) { result[$0].lowercased() }
            let clashes = groups.values.filter { $0.count > 1 }
            guard !clashes.isEmpty else { break }
            for group in clashes {
                for index in group {
                    result[index] = label(trimmed[index], length: length)
                }
            }
        }
        return result
    }

    var initials: [String] { Self.initials(for: people.map(\.name)) }

    func summaryText() -> String {
        var lines = shares().map { "\($0.person.name) = \(Money.format($0.total))" }
        lines.append("Total = \(Money.format(total))")
        return lines.joined(separator: "\n")
    }

    /// Splits `cents` into `count` near-equal parts that add up exactly.
    static func split(_ cents: Int, into count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let base = cents / count
        let remainder = cents % count
        return (0..<count).map { $0 < abs(remainder) ? base + remainder.signum() : base }
    }

    /// Splits `amount` in proportion to `weights` (largest-remainder method),
    /// falling back to an even split when nobody has a positive weight.
    static func distribute(_ amount: Int, weights: [Int]) -> [Int] {
        guard !weights.isEmpty else { return [] }
        let positive = weights.map { max($0, 0) }
        let totalWeight = positive.reduce(0, +)
        guard totalWeight > 0 else { return split(amount, into: weights.count) }

        let sign = amount < 0 ? -1 : 1
        let magnitude = abs(amount)
        var result = positive.map { magnitude * $0 / totalWeight }
        var leftover = magnitude - result.reduce(0, +)
        let byRemainder = positive.indices.sorted {
            (magnitude * positive[$0]) % totalWeight > (magnitude * positive[$1]) % totalWeight
        }
        var next = 0
        while leftover > 0 {
            result[byRemainder[next % byRemainder.count]] += 1
            leftover -= 1
            next += 1
        }
        return result.map { $0 * sign }
    }
}
