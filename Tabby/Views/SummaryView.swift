import SwiftUI

struct SummaryView: View {
    @Environment(BillSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(PeopleStore.self) private var store
    @State private var copied = false

    var body: some View {
        let shares = session.shares()
        let text = session.summaryText()
        let unassigned = session.unassignedItems.count

        List {
            Section {
                ForEach(shares) { share in
                    DisclosureGroup {
                        ForEach(share.entries) { entry in
                            LabeledContent {
                                Text(Money.format(entry.amount)).monospacedDigit()
                            } label: {
                                Text(entry.name.isEmpty ? "Untitled item" : entry.name)
                                if entry.splitCount > 1 {
                                    Text("Split \(entry.splitCount) ways")
                                }
                            }
                        }
                        if share.extras != 0 {
                            LabeledContent("Tax & tip") {
                                Text(Money.format(share.extras)).monospacedDigit()
                            }
                        }
                    } label: {
                        HStack {
                            Text(share.person.name)
                                .font(.headline)
                            Spacer()
                            Text(Money.format(share.total))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                }
            } footer: {
                Text("Tax and tip are split in proportion to what each person ordered.")
            }

            if unassigned > 0 {
                Section {
                    Label("\(unassigned) item\(unassigned == 1 ? "" : "s") not assigned to anyone",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                LabeledContent("Bill total") {
                    Text(Money.format(session.total)).bold().monospacedDigit()
                }
            }

            Section("Copy text") {
                Text(text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Shares")
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                ShareLink(item: text) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Bill") {
                    session.startNewBill()
                    router.path = []
                }
            }
        }
        .sensoryFeedback(.success, trigger: copied) { _, isCopied in isCopied }
        .onAppear {
            store.remember(session.people.map(\.name))
        }
    }
}
