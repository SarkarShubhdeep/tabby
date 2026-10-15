import Foundation
import Observation

/// Names the user has split with before, saved on device so they can be
/// re-added with one tap. Most recent first.
@Observable
final class PeopleStore {
    private static let key = "savedPeople"
    private static let limit = 30

    private let defaults: UserDefaults
    private(set) var names: [String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        names = defaults.stringArray(forKey: Self.key) ?? []
    }

    func remember(_ newNames: [String]) {
        var updated = names
        for raw in newNames.reversed() {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Single letters are the A/B/C placeholders, not worth saving.
            guard name.count > 1 else { continue }
            updated.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
            updated.insert(name, at: 0)
        }
        names = Array(updated.prefix(Self.limit))
        save()
    }

    func forget(_ name: String) {
        names.removeAll { $0 == name }
        save()
    }

    private func save() {
        defaults.set(names, forKey: Self.key)
    }
}
