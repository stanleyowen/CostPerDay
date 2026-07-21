import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var customCategories: [CustomCategory]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault

    @State private var isEditing = false
    @State private var confirmingDelete = false

    private var isForeign: Bool { item.currencyCode != baseCurrency }
    private var category: CategoryDisplay {
        CategoryCatalog(custom: customCategories).display(for: item.categoryKey)
    }

    var body: some View {
        List {
            Section {
                CostComparison(item: item, currency: baseCurrency)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Lifetime") {
                LabeledContent("Owned for", value: Duration.fromDays(item.daysOwned()))
                LabeledContent("Expected life", value: Duration.fromMonths(item.expectedLifetimeMonths))
                if let retired = item.retiredDate {
                    LabeledContent("Retired", value: retired.formatted(date: .abbreviated, time: .omitted))
                } else if item.isPaidOff() {
                    LabeledContent("Status") {
                        Label("Fully amortised — every further day is free", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    }
                } else {
                    LabeledContent("Reaches expected end of life", value: item.expectedEndDate.formatted(date: .abbreviated, time: .omitted))
                    LabeledContent("Days remaining", value: "\(item.daysRemaining())")
                }

                VStack(alignment: .leading, spacing: 6) {
                    LifetimeBar(progress: item.lifetimeProgress(), tint: category.tint, height: 8)
                    Text("\(Int((min(item.lifetimeProgress(), 9.99) * 100).rounded()))% of expected lifetime elapsed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Purchase") {
                LabeledContent("Price", value: Money.string(item.price, code: item.currencyCode))
                if isForeign {
                    LabeledContent("Rate at purchase", value: "1 \(item.currencyCode) = \(item.effectiveRate.formatted(.number.precision(.fractionLength(0...6)))) \(baseCurrency)")
                    LabeledContent("In \(baseCurrency)", value: Money.string(item.priceInBase, code: baseCurrency))
                }
                if item.resaleValue > 0 {
                    LabeledContent("Recovered on resale", value: Money.string(item.resaleValue, code: item.currencyCode))
                    LabeledContent("Net cost", value: Money.string(item.netCost, code: baseCurrency))
                }
                LabeledContent("Bought", value: item.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("Category") {
                    Label(category.label, systemImage: category.symbol)
                        .foregroundStyle(category.isMissing ? Color.secondary : category.tint)
                }
                LabeledContent("Sector", value: category.sector.label)
                if !item.brand.isEmpty {
                    LabeledContent("Brand", value: item.brand)
                }
            }

            if !item.notes.isEmpty {
                Section("Notes") {
                    Text(item.notes)
                }
            }

            Section {
                if item.isRetired {
                    Button("Return to service") { item.retiredDate = nil }
                } else {
                    Button("Retire this item") { item.retiredDate = .now }
                }
                Button("Delete", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Retiring an item stops its cost calculation while retaining it in your history and statistics.")
            }
        }
        .navigationTitle(item.name.isEmpty ? String(localized: "Untitled", comment: "Fallback name for an unnamed item") : item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            ItemEditView(item: item, isNew: false)
        }
        .confirmationDialog(
            Text("Delete \(item.name.isEmpty ? String(localized: "this item", comment: "Used in a delete confirmation when the item has no name") : item.name)?"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                context.delete(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the item from your history and statistics. If you have simply stopped using it, retire it instead.")
        }
    }
}

/// Side-by-side "so far" vs "planned" — the toggleable comparison, shown as one view.
private struct CostComparison: View {
    let item: Item
    let currency: String

    var body: some View {
        HStack(spacing: 0) {
            figure(
                value: item.actualCostPerDay(),
                title: String(localized: "To date", comment: "Cost basis: cost per day so far"),
                caption: String(localized: "over \(Duration.fromDays(item.daysOwned()))", comment: "Caption under a cost figure. The placeholder is a duration."),
                emphasised: true
            )
            Divider().frame(height: 60)
            figure(
                value: item.plannedCostPerDay,
                title: String(localized: "Planned", comment: "Cost basis: cost per day as budgeted"),
                caption: String(localized: "over \(Duration.fromMonths(item.expectedLifetimeMonths))", comment: "Caption under a cost figure. The placeholder is a duration."),
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
