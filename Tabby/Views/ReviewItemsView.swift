import SwiftUI

struct ReviewItemsView: View {
    @Environment(BillSession.self) private var session
    @Environment(Router.self) private var router
    @FocusState private var focusedItem: UUID?

    private let priceFormat = Decimal.FormatStyle(locale: .current).precision(.fractionLength(2))

    var body: some View {
        @Bindable var session = session
        List {
            if let warning = mismatchWarning {
                Section {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if session.items.isEmpty {
                    Text("No items yet. Add them below.")
                        .foregroundStyle(.secondary)
                }
                ForEach($session.items) { $item in
                    HStack {
                        TextField("Item", text: $item.name)
                            .focused($focusedItem, equals: item.id)
                        TextField("0.00", value: $item.price, format: priceFormat)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(maxWidth: 100)
                    }
                }
                .onDelete { session.items.remove(atOffsets: $0) }
                Button {
                    let item = LineItem(name: "", price: 0)
                    session.items.append(item)
                    focusedItem = item.id
                } label: {
                    Label("Add Item", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Items (\(session.items.count))")
            } footer: {
                Text("Tap to fix a name or price. Swipe left to delete.")
            }

            Section("Tax & Tip") {
                moneyRow("Tax", value: $session.tax)
                moneyRow("Tip", value: $session.tip)
            }

            Section {
                LabeledContent("Items", value: Money.format(session.itemsSubtotal))
                LabeledContent("Total") {
                    Text(Money.format(session.total)).bold()
                }
            }
        }
        .navigationTitle("Review Bill")
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { router.path.append(.people) }
                    .disabled(session.items.isEmpty)
            }
        }
    }

    private var mismatchWarning: String? {
        guard let receipt = session.receiptSubtotal, receipt != session.itemsSubtotal else { return nil }
        return "Items add up to \(Money.format(session.itemsSubtotal)), but the receipt says \(Money.format(receipt)). Check for missed or misread lines."
    }

    private func moneyRow(_ title: String, value: Binding<Decimal>) -> some View {
        LabeledContent(title) {
            TextField("0.00", value: value, format: priceFormat)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}
