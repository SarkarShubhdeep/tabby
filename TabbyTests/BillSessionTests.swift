import XCTest
@testable import Tabby

final class BillSessionTests: XCTestCase {
    private func d(_ string: String) -> Decimal {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))!
    }

    func testSplitAddsUpExactly() {
        XCTAssertEqual(BillSession.split(1000, into: 3), [334, 333, 333])
        XCTAssertEqual(BillSession.split(-1000, into: 3), [-334, -333, -333])
        XCTAssertEqual(BillSession.split(5, into: 0), [])
    }

    func testDistributeIsProportionalAndExact() {
        let parts = BillSession.distribute(100, weights: [1, 1, 1])
        XCTAssertEqual(parts.reduce(0, +), 100)
        XCTAssertEqual(parts.sorted(), [33, 33, 34])
        XCTAssertEqual(BillSession.distribute(300, weights: [1000, 2000]), [100, 200])
        XCTAssertEqual(BillSession.distribute(90, weights: [0, 0, 0]), [30, 30, 30])
    }

    func testSharesWithTaxAndTip() {
        let session = BillSession()
        session.addPerson(named: "Adele")
        session.addPerson(named: "Bob")
        let adele = session.people[0].id
        let bob = session.people[1].id
        session.items = [
            LineItem(name: "Steak", price: d("30.00"), assignees: [adele]),
            LineItem(name: "Salad", price: d("10.00"), assignees: [bob]),
            LineItem(name: "Wine", price: d("20.00"), assignees: [adele, bob]),
        ]
        session.tax = d("4.00")
        session.tip = d("8.00")

        let shares = session.shares()
        // Adele: 30 + 10 = 40 (2/3), Bob: 10 + 10 = 20 (1/3); extras 12 → 8 / 4.
        XCTAssertEqual(shares[0].subtotal, d("40"))
        XCTAssertEqual(shares[0].total, d("48"))
        XCTAssertEqual(shares[1].total, d("24"))
        XCTAssertEqual(shares.reduce(Decimal(0)) { $0 + $1.total }, session.total)
        XCTAssertEqual(session.summaryText().split(separator: "\n").count, 3)
    }

    func testRemovingPersonClearsAssignments() {
        let session = BillSession()
        session.addPerson(named: "A")
        session.addPerson(named: "B")
        let a = session.people[0].id
        session.items = [LineItem(name: "Tea", price: 3, assignees: [a])]
        session.removePeople(at: [0])
        XCTAssertTrue(session.items[0].assignees.isEmpty)
        XCTAssertEqual(session.unassignedItems.count, 1)
    }

    func testDuplicateNamesAreRejected() {
        let session = BillSession()
        XCTAssertTrue(session.addPerson(named: "Bob"))
        XCTAssertFalse(session.addPerson(named: " bob "))
        XCTAssertFalse(session.addPerson(named: "  "))
    }

    func testKeyLetters() {
        XCTAssertEqual(BillSession.keyLetter(for: 0), "A")
        XCTAssertEqual(BillSession.keyLetter(for: 25), "Z")
        XCTAssertEqual(BillSession.keyLetter(for: 26), "")
    }

    func testPeopleStoreRemembersMostRecentFirst() {
        let defaults = UserDefaults(suiteName: "tabby-tests-\(UUID().uuidString)")!
        let store = PeopleStore(defaults: defaults)
        store.remember(["Adele", "Bob", "A"])
        store.remember(["Carmen", "adele"])
        XCTAssertEqual(store.names, ["Carmen", "adele", "Bob"])
        XCTAssertEqual(PeopleStore(defaults: defaults).names, ["Carmen", "adele", "Bob"])
        store.forget("Bob")
        XCTAssertEqual(store.names, ["Carmen", "adele"])
    }
}
