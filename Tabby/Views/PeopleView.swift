import SwiftUI

struct PeopleView: View {
    @Environment(BillSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(PeopleStore.self) private var store
    @State private var newName = ""
    @FocusState private var isAdding: Bool

    var body: some View {
        @Bindable var session = session
        List {
            Section {
                ForEach($session.people) { $person in
                    HStack(spacing: 12) {
                        KeyBadge(letter: letter(for: person))
                        TextField("Name", text: $person.name)
                            .textInputAutocapitalization(.words)
                    }
                }
                .onDelete { session.removePeople(at: $0) }

                HStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    TextField("Add a person", text: $newName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($isAdding)
                        .onSubmit(addTypedName)
                }

                if session.people.isEmpty {
                    Button {
                        for placeholder in ["A", "B", "C"] {
                            session.addPerson(named: placeholder)
                        }
                    } label: {
                        Label("Just use A, B, C", systemImage: "textformat.abc")
                    }
                }
            } header: {
                Text("Who's splitting?")
            } footer: {
                Text("Everyone gets a letter. On the next screen, tap their badge or type their letter.")
            }

            if !suggestions.isEmpty {
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(suggestions, id: \.self) { name in
                            Button {
                                _ = session.addPerson(named: name)
                            } label: {
                                Label(name, systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .contextMenu {
                                Button("Forget \(name)", systemImage: "trash", role: .destructive) {
                                    store.forget(name)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Recent")
                } footer: {
                    Text("Touch and hold a name to forget it.")
                }
            }
        }
        .navigationTitle("People")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") {
                    addTypedName()
                    session.normalizePeopleNames()
                    store.remember(session.people.map(\.name))
                    router.path.append(.assign)
                }
                .disabled(session.people.isEmpty && newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// Saved names that aren't already on this bill.
    private var suggestions: [String] {
        store.names.filter { name in
            !session.people.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
    }

    private func letter(for person: Person) -> String {
        BillSession.keyLetter(for: session.people.firstIndex { $0.id == person.id } ?? 0)
    }

    private func addTypedName() {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if session.addPerson(named: newName) {
            store.remember([newName])
        }
        newName = ""
        isAdding = true
    }
}
