import SwiftUI
import SwiftData

/// On an item's page: the transactions behind it — the purchase and any upkeep —
/// and what owning it really costs per day once upkeep is counted.
struct ItemSpendingCard: View {
    let item: Item
    let daysOwned: Int
    let currency: String
    let onLink: () -> Void

    @Query private var accounts: [Account]
    @Environment(\.modelContext) private var context

    var body: some View {
        let linked = item.linkedRecords
        let upkeep = item.upkeepInBase
        VStack(alignment: .leading, spacing: 4) {
            CardHeader(
                title: String(localized: "Transactions", comment: "Card title on an item"),
                subtitle: linked.isEmpty
                    ? String(localized: "Link the purchase and any repairs or accessories to see the full cost of ownership.", comment: "Card subtitle")
                    : nil
            )
            .padding(.bottom, 4)

            if !linked.isEmpty {
                if upkeep > 0 {
                    InfoRow("Upkeep", value: Money.string(upkeep, code: currency))
                    Divider()
                    InfoRow("Total cost of ownership", value: Money.string(item.netCost + upkeep, code: currency))
                    Divider()
                    InfoRow("Including upkeep") {
                        Text(Money.perDay(item.totalCostPerDay(), code: currency) + " " + String(localized: "per day"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.accent)
                    }
                    Divider()
                }
                ForEach(linked) { record in
                    let flow = record.flow
                    RecordLink(record: record) {
                        HStack(spacing: 10) {
                            CategoryTile(symbol: flow.category.symbol, tint: flow.category.tint, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(flow.note.split(separator: "\n").first.map(String.init) ?? flow.category.label)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(record.isItemPurchase ? String(localized: "Purchase") : String(localized: "Upkeep")) · \(flow.date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Money.signed(flow.safeAmount, code: flow.currencyCode, kind: flow.kind))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            Button(action: onLink) {
                Label("Link a transaction", systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .padding(.top, 8)
        }
        .card()
    }
}

/// Find a transaction to attach to an item — as its purchase, or as upkeep.
struct LinkRecordSheet: View {
    let item: Item

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Record> { $0.item == nil }, sort: \Record.date, order: .reverse) private var records: [Record]
    @Query private var accounts: [Account]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @State private var search = ""
    @State private var asPurchase = false

    var body: some View {
        let ledger = LedgerSnapshot(accounts: accounts, records: [], baseCurrency: baseCurrency)
        let query = search.trimmingCharacters(in: .whitespaces)
        // Purchases near the item's purchase date first when nothing's typed.
        let pool = records.filter { $0.kind != .income }
        let results: [Record] = query.isEmpty
            ? Array(pool.sorted { abs($0.date.timeIntervalSince(item.purchaseDate)) < abs($1.date.timeIntervalSince(item.purchaseDate)) }.prefix(60))
            : Array(pool.filter { $0.note.localizedCaseInsensitiveContains(query) || $0.payee.localizedCaseInsensitiveContains(query) || $0.labels.contains { $0.localizedCaseInsensitiveContains(query) } }.prefix(100))
        let hasPurchase = (item.records ?? []).contains(where: \.isItemPurchase)

        NavigationStack {
            List {
                if !hasPurchase {
                    Section {
                        Picker("Link as", selection: $asPurchase) {
                            Text("Upkeep").tag(false)
                            Text("Purchase").tag(true)
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text(asPurchase
                             ? "The purchase is already counted in the item's price, so it won't be added again."
                             : "Upkeep is added on top of the purchase price — repairs, accessories, servicing.")
                    }
                }
                Section(query.isEmpty ? String(localized: "Around the purchase date") : String(localized: "Results")) {
                    ForEach(results) { record in
                        Button {
                            record.item = item
                            record.isItemPurchase = asPurchase && !hasPurchase
                            try? context.save()
                            dismiss()
                        } label: {
                            RecordRow(flow: record.flow, accountLine: ledger.accountLine(for: record.flow), showsDate: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $search, prompt: Text("Search transactions"))
            .navigationTitle("Link a transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { CancelButton { dismiss() } }
            }
            .onAppear { asPurchase = !hasPurchase && (item.records ?? []).isEmpty }
        }
    }
}

extension RecordDraft: Identifiable {
    var id: String { "\(kind.rawValue)|\(date.timeIntervalSince1970)|\(amount)|\(note)" }
}

/// Choose one of your tracked items, to file a transaction as upkeep on it.
struct ItemPickerSheet: View {
    let onPick: (Item) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Item.purchaseDate, order: .reverse) private var items: [Item]
    @Query private var customCategories: [CustomCategory]
    @State private var search = ""

    var body: some View {
        let catalog = CategoryCatalog(custom: customCategories)
        let filtered = items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.brand.localizedCaseInsensitiveContains(search) }
        NavigationStack {
            List(filtered) { item in
                Button {
                    onPick(item)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ItemGlyph(category: catalog.display(for: item.categoryKey), progress: item.lifetimeProgress(), isRetired: item.isRetired, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName).foregroundStyle(.primary)
                            Text(item.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("No tracked items", systemImage: "shippingbox", description: Text("Track a purchase as an item first."))
                }
            }
            .searchable(text: $search, prompt: Text("Search items"))
            .navigationTitle("Add as upkeep to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { CancelButton { dismiss() } }
            }
        }
    }
}
