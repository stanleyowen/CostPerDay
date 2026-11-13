import SwiftUI
import SwiftData

/// One transaction in full, and the bridge to the ownership tracker: any purchase
/// can become a tracked item, or be filed as upkeep on one you already track.
struct RecordDetailView: View {
    @Bindable var record: Record

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @Query private var customCategories: [CustomCategory]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault

    @State private var editing = false
    @State private var duplicating: RecordDraft?
    @State private var confirmingDelete = false
    @State private var newItem: Item?
    @State private var choosingItem = false
    @State private var linkTrigger = 0

    private func account(_ id: UUID?) -> Account? { id.flatMap { id in accounts.first { $0.uuid == id } } }

    var body: some View {
        let flow = record.flow
        let category = flow.category

        ScrollView {
            VStack(spacing: 16) {
                header(flow: flow, category: category)
                detailsCard(flow: flow, category: category)
                if !record.note.isEmpty && record.note.contains("\n") {
                    VStack(alignment: .leading, spacing: 8) {
                        CardHeader(title: String(localized: "Note"))
                        Text(record.note)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .card()
                }
                if record.kind != .income || record.item != nil {
                    lifecycleCard(flow: flow)
                }
                actions
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(record.kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { editing = true }
        }
        .sheet(isPresented: $editing) {
            RecordEditView(record: record)
        }
        .sheet(item: $duplicating) { draft in
            RecordEditView(record: nil, prefill: draft)
        }
        .sheet(item: $newItem) { item in
            ItemEditView(item: item, isNew: true, prefilled: true)
        }
        .sheet(isPresented: $choosingItem) {
            ItemPickerSheet { item in
                withAnimation(.snappy) {
                    record.item = item
                    record.isItemPurchase = false
                    linkTrigger += 1
                }
                try? context.save()
            }
        }
        .confirmationDialog(Text("Delete this transaction?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(record)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Account balances and reports will update. A tracked item linked to it is kept.")
        }
        .sensoryFeedback(.success, trigger: linkTrigger)
    }

    private func header(flow: Flow, category: RecordCategoryDisplay) -> some View {
        VStack(spacing: 10) {
            CategoryTile(symbol: category.symbol, tint: category.tint, size: 68)
            Text(Money.signed(flow.safeAmount, code: flow.currencyCode, kind: flow.kind))
                .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(flow.kind == .income ? AnyShapeStyle(Color.income) : AnyShapeStyle(.primary))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .sensitive()
            if flow.currencyCode != baseCurrency, flow.kind != .transfer {
                Text(verbatim: "≈ \(Money.exact(flow.baseAmount, code: baseCurrency))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(headline(flow: flow, category: category))
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(flow.date.formatted(date: .complete, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func headline(flow: Flow, category: RecordCategoryDisplay) -> String {
        let firstLine = flow.note.split(separator: "\n").first.map(String.init) ?? ""
        if !firstLine.isEmpty { return firstLine }
        if !flow.payee.isEmpty { return flow.payee }
        return category.label
    }

    private func detailsCard(flow: Flow, category: RecordCategoryDisplay) -> some View {
        let outside = String(localized: "Outside Wallet", comment: "Transfer endpoint that isn't a tracked account")
        return VStack(alignment: .leading, spacing: 0) {
            if flow.kind == .transfer {
                InfoRow("From", value: account(flow.accountID)?.displayName ?? outside)
                Divider()
                InfoRow("To", value: account(flow.toAccountID)?.displayName ?? outside)
                if flow.toAmount > 0, let destination = account(flow.toAccountID), destination.currencyCode != flow.currencyCode {
                    Divider()
                    InfoRow("Received", value: Money.exact(flow.toAmount, code: destination.currencyCode))
                }
            } else {
                InfoRow("Account", value: account(flow.accountID)?.displayName ?? String(localized: "Deleted account"))
                Divider()
                InfoRow("Category") {
                    Label(category.isMissing || category.group == .other || RecordCategory(rawValue: category.key)?.isGeneral == true
                          ? category.label
                          : "\(category.group.label) › \(category.label)",
                          systemImage: category.symbol)
                        .foregroundStyle(category.tint)
                        .lineLimit(2)
                }
            }
            if !flow.payee.isEmpty {
                Divider()
                InfoRow("Payee", value: flow.payee)
            }
            if !flow.note.isEmpty && !flow.note.contains("\n") {
                Divider()
                InfoRow("Note", value: flow.note)
            }
            if !flow.labels.isEmpty {
                Divider()
                InfoRow("Labels") { LabelChips(labels: flow.labels) }
            }
            if flow.currencyCode != baseCurrency {
                Divider()
                InfoRow("Rate", value: "1 \(flow.currencyCode) = \(Flow.safeRate(flow.rateToBase).formatted(.number.precision(.fractionLength(0...4)))) \(baseCurrency)")
            }
            if record.importKey != nil {
                Divider()
                InfoRow("Source", value: String(localized: "Imported from BudgetBakers", comment: "Transaction source"))
            }
        }
        .card(padding: 16)
    }

    @ViewBuilder
    private func lifecycleCard(flow: Flow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(
                title: String(localized: "Ownership", comment: "Card title"),
                subtitle: record.item == nil
                    ? String(localized: "Bought something that lasts? Track what it costs you per day.", comment: "Card subtitle")
                    : nil
            )
            if let item = record.item {
                let category = CategoryCatalog(custom: customCategories).display(for: item.categoryKey)
                NavigationLink {
                    ItemDetailView(item: item)
                } label: {
                    HStack(spacing: 12) {
                        ItemGlyph(category: category, progress: item.lifetimeProgress(), isRetired: item.isRetired, size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(record.isItemPurchase
                                 ? String(localized: "Purchase", comment: "Role of a transaction linked to an item")
                                 : String(localized: "Upkeep", comment: "Role of a transaction linked to an item"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Brand.accent)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Money.perDay(item.totalCostPerDay(), code: baseCurrency))
                                .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                                .foregroundStyle(.primary)
                            Text("per day").font(.caption2).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Button("Unlink", systemImage: "link.badge.plus") {
                    withAnimation(.snappy) {
                        record.item = nil
                        record.isItemPurchase = false
                    }
                    try? context.save()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Button {
                        newItem = LedgerActions.trackAsItem(record, in: context)
                    } label: {
                        Label("Track as item", systemImage: "shippingbox.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    Button {
                        choosingItem = true
                    } label: {
                        Label("Add as upkeep", systemImage: "wrench.and.screwdriver.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                }
            }
        }
        .card()
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                var copy = RecordDraft(record: record)
                copy.date = .now
                duplicating = copy
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 16))

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 16))
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
