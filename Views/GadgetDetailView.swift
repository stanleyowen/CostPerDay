import SwiftUI
import SwiftData

struct GadgetDetailView: View {
    @Bindable var gadget: Gadget
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault

    @State private var isEditing = false
    @State private var confirmingDelete = false

    private var isForeign: Bool { gadget.currencyCode != baseCurrency }

    var body: some View {
        List {
            Section {
                CostComparison(gadget: gadget, currency: baseCurrency)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Lifetime") {
                LabeledContent("Owned for", value: Duration.fromDays(gadget.daysOwned()))
                LabeledContent("Expected life", value: Duration.fromMonths(gadget.expectedLifetimeMonths))
                if let retired = gadget.retiredDate {
                    LabeledContent("Retired", value: retired.formatted(date: .abbreviated, time: .omitted))
                } else if gadget.isPaidOff() {
                    LabeledContent("Status") {
                        Label("Paid off — every day from here is free", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    }
                } else {
                    LabeledContent("Breaks even", value: gadget.expectedEndDate.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Days left", value: "\(gadget.daysRemaining())")
                }

                VStack(alignment: .leading, spacing: 6) {
                    LifetimeBar(progress: gadget.lifetimeProgress(), tint: gadget.category.tint, height: 8)
                    Text("\(Int((min(gadget.lifetimeProgress(), 9.99) * 100).rounded()))% through its expected life")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Purchase") {
                LabeledContent("Price", value: Money.string(gadget.price, code: gadget.currencyCode))
                if isForeign {
                    LabeledContent("Rate at purchase", value: "1 \(gadget.currencyCode) = \(gadget.effectiveRate.formatted(.number.precision(.fractionLength(0...6)))) \(baseCurrency)")
                    LabeledContent("In \(baseCurrency)", value: Money.string(gadget.priceInBase, code: baseCurrency))
                }
                if gadget.resaleValue > 0 {
                    LabeledContent("Recovered on resale", value: Money.string(gadget.resaleValue, code: gadget.currencyCode))
                    LabeledContent("Net cost", value: Money.string(gadget.netCost, code: baseCurrency))
                }
                LabeledContent("Bought", value: gadget.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Category") {
                    Label(gadget.category.label, systemImage: gadget.category.symbol)
                        .foregroundStyle(gadget.category.tint)
                }
                if !gadget.brand.isEmpty {
                    LabeledContent("Brand", value: gadget.brand)
                }
            }

            if !gadget.notes.isEmpty {
                Section("Notes") {
                    Text(gadget.notes)
                }
            }

            Section {
                if gadget.isRetired {
                    Button("Put back in service") { gadget.retiredDate = nil }
                } else {
                    Button("Retire this gadget") { gadget.retiredDate = .now }
                }
                Button("Delete", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Retiring stops the cost clock but keeps the item in your history and stats.")
            }
        }
        .navigationTitle(gadget.name.isEmpty ? "Untitled" : gadget.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            GadgetEditView(gadget: gadget, isNew: false)
        }
        .confirmationDialog(
            "Delete \(gadget.name.isEmpty ? "this gadget" : gadget.name)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                context.delete(gadget)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes it from your history and stats. Retire it instead if you just stopped using it.")
        }
    }
}

/// Side-by-side "so far" vs "planned" — the toggleable comparison, shown as one view.
private struct CostComparison: View {
    let gadget: Gadget
    let currency: String

    var body: some View {
        HStack(spacing: 0) {
            figure(
                value: gadget.actualCostPerDay(),
                title: "So far",
                caption: "over \(Duration.fromDays(gadget.daysOwned()))",
                emphasised: true
            )
            Divider().frame(height: 60)
            figure(
                value: gadget.plannedCostPerDay,
                title: "Planned",
                caption: "over \(Duration.fromMonths(gadget.expectedLifetimeMonths))",
                emphasised: false
            )
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private func figure(value: Double, title: String, caption: String, emphasised: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(Money.perDay(value, code: currency))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(emphasised ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("per day")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
