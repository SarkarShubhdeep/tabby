import SwiftUI

struct SummaryView: View {
    @Environment(BillSession.self) private var session
    @Environment(Router.self) private var router
    @Environment(PeopleStore.self) private var store
    @State private var copied = false
    @State private var annotatedReceipt: UIImage?
    @State private var isSharing = false
    @State private var isViewingReceipt = false

    var body: some View {
        let shares = session.shares()
        let text = session.summaryText()
        let unassigned = session.unassignedItems.count
        let initials = session.initials

        List {
            Section {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
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
                            Text(initials[index])
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Color(uiColor: ReceiptAnnotator.color(for: index)), in: Circle())
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

            if !session.receiptPages.isEmpty {
                Section {
                    Group {
                        if let annotatedReceipt {
                            Button {
                                isViewingReceipt = true
                            } label: {
                                Image(uiImage: annotatedReceipt)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 360)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 120)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Marked-up receipt")
                } footer: {
                    Text("Shared along with the text. Tap to view full size.")
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

                if let annotatedReceipt {
                    Button {
                        isSharing = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $isSharing) {
                        ActivityView(items: [annotatedReceipt, text])
                            .presentationDetents([.medium, .large])
                    }
                } else {
                    ShareLink(item: text) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
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
        .task {
            guard let job = session.annotationJob() else { return }
            annotatedReceipt = await Task.detached(priority: .userInitiated) { job() }.value
        }
        .sheet(isPresented: $isViewingReceipt) {
            if let annotatedReceipt {
                NavigationStack {
                    ScrollView {
                        Image(uiImage: annotatedReceipt)
                            .resizable()
                            .scaledToFit()
                    }
                    .navigationTitle("Receipt")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isViewingReceipt = false }
                        }
                    }
                }
            }
        }
    }
}
