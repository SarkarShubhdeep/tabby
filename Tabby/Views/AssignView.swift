import SwiftUI

/// One item per screen: tap (or type) who had it, then Next.
struct AssignView: View {
    @Environment(BillSession.self) private var session
    @Environment(Router.self) private var router
    @State private var index = 0
    @State private var typed = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        if session.items.isEmpty || session.people.isEmpty {
            ContentUnavailableView("Nothing to split", systemImage: "list.bullet.rectangle")
        } else {
            content
        }
    }

    private var content: some View {
        let current = min(index, session.items.count - 1)
        let item = session.items[current]
        let isLast = current == session.items.count - 1

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(current + 1), total: Double(session.items.count))
                Text("Item \(current + 1) of \(session.items.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text(item.name.isEmpty ? "Untitled item" : item.name)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(Money.format(item.price))
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(caption(for: item))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 16)

                    FlowLayout(spacing: 10) {
                        ForEach(Array(session.people.enumerated()), id: \.element.id) { offset, person in
                            PersonChip(letter: BillSession.keyLetter(for: offset),
                                       name: person.name,
                                       isSelected: item.assignees.contains(person.id)) {
                                toggle(person.id)
                            }
                        }
                        Button {
                            toggleEveryone()
                        } label: {
                            Label("Everyone", systemImage: "person.3.fill")
                                .padding(.vertical, 12)
                                .padding(.horizontal, 14)
                                .background(Color(.secondarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Image(systemName: "keyboard")
                            .foregroundStyle(.secondary)
                        TextField("Or type letters, e.g. AB", text: $typed)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(isLast ? .done : .next)
                            .focused($isTyping)
                            .onSubmit {
                                advance()
                                isTyping = true
                            }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 12) {
                Button {
                    index = current - 1
                } label: {
                    Text("Back").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(current == 0)

                Button {
                    advance()
                } label: {
                    Text(isLast ? "See Shares" : "Next").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(item.assignees.isEmpty)
            }
            .controlSize(.large)
            .padding()
        }
        .navigationTitle("Who had this?")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: item.assignees)
        .onAppear(perform: syncTyped)
        .onChange(of: index) { syncTyped() }
        .onChange(of: typed) { _, text in applyTyped(text) }
    }

    // MARK: - Actions

    private var currentIndex: Int { min(index, session.items.count - 1) }

    private func caption(for item: LineItem) -> String {
        let owners = session.people.filter { item.assignees.contains($0.id) }
        switch owners.count {
        case 0: return "Tap who had this"
        case 1: return owners[0].name
        default: return "Split \(owners.count) ways · \(Money.format(item.price / Decimal(owners.count))) each"
        }
    }

    private func toggle(_ id: UUID) {
        let i = currentIndex
        if session.items[i].assignees.contains(id) {
            session.items[i].assignees.remove(id)
        } else {
            session.items[i].assignees.insert(id)
        }
        syncTyped()
    }

    private func toggleEveryone() {
        let i = currentIndex
        let everyone = Set(session.people.map(\.id))
        session.items[i].assignees = session.items[i].assignees.isSuperset(of: everyone) ? [] : everyone
        syncTyped()
    }

    private func advance() {
        let i = currentIndex
        guard !session.items[i].assignees.isEmpty else { return }
        if i < session.items.count - 1 {
            index = i + 1
        } else {
            isTyping = false
            router.path.append(.summary)
        }
    }

    /// Typing "ab" or "a, b" selects people A and B.
    private func applyTyped(_ text: String) {
        let letters = Set(text.uppercased().compactMap { $0.isLetter ? String($0) : nil })
        let ids = session.people.enumerated()
            .filter { letters.contains(BillSession.keyLetter(for: $0.offset)) }
            .map(\.element.id)
        let selection = Set(ids)
        if session.items[currentIndex].assignees != selection {
            session.items[currentIndex].assignees = selection
        }
    }

    /// Mirrors the current selection into the text field.
    private func syncTyped() {
        guard !session.items.isEmpty else { return }
        let assignees = session.items[currentIndex].assignees
        let letters = session.people.enumerated()
            .filter { assignees.contains($0.element.id) }
            .map { BillSession.keyLetter(for: $0.offset) }
            .joined()
        if letters != typed.uppercased().filter(\.isLetter) {
            typed = letters
        }
    }
}
