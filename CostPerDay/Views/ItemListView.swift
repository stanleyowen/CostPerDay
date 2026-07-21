import SwiftUI
import SwiftData

struct ItemListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.purchaseDate, order: .reverse) private var items: [Item]
    @Query private var customCategories: [CustomCategory]

    @AppStorage("costMode") private var costModeRaw = CostMode.actual.rawValue
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @State private var sort: SortOption = .costPerDay
    @State private var showRetired = false
    @State private var sectorFilter: Sector?
    @State private var newItem: Item?
    @State private var deletedNotice: String?

    private var costMode: CostMode { CostMode(rawValue: costModeRaw) ?? .actual }
    private var catalog: CategoryCatalog { CategoryCatalog(custom: customCategories) }

    enum SortOption: String, CaseIterable, Identifiable {
        case costPerDay, price, newest, name
        var id: String { rawValue }

        var label: String {
            switch self {
            case .costPerDay: String(localized: "Cost per day", comment: "Sort option")
            case .price: String(localized: "Price", comment: "Sort option")
            case .newest: String(localized: "Most recent", comment: "Sort option")
            case .name: String(localized: "Name", comment: "Sort option")
            }
        }
    }

    /// Sectors that actually have something in them — no point offering a filter
    /// that would return an empty list.
    private var availableSectors: [Sector] {
        let present = Set(items.map { catalog.display(for: $0.categoryKey).sector })
        return Sector.allCases.filter { present.contains($0) }
    }

    private var visible: [Item] {
        let catalog = self.catalog
        var pool = items.filter { showRetired || !$0.isRetired }
        if let sectorFilter {
            pool = pool.filter { catalog.display(for: $0.categoryKey).sector == sectorFilter }
        }
        switch sort {
        case .costPerDay: return pool.sorted { $0.costPerDay(mode: costMode) > $1.costPerDay(mode: costMode) }
        case .price: return pool.sorted { $0.netCost > $1.netCost }
        case .newest: return pool.sorted { $0.purchaseDate > $1.purchaseDate }
        case .name: return pool.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// The burn rate always reflects everything you still own, regardless of any
    /// sector filter — it's the total you're trying to keep down.
    private var activeItems: [Item] { items.filter { !$0.isRetired } }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyStateView { addItem() }
                } else {
                    list
                }
            }
            .navigationTitle("Items")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(SortOption.allCases) { Text($0.label).tag($0) }
                        }
                        if availableSectors.count > 1 {
                            Divider()
                            Picker("Sector", selection: $sectorFilter) {
                                Text("All sectors").tag(Sector?.none)
                                ForEach(availableSectors) { sector in
                                    Label(sector.label, systemImage: sector.symbol).tag(Sector?.some(sector))
                                }
                            }
                        }
                        Divider()
                        Toggle("Show retired", isOn: $showRetired)
                        #if DEBUG
                        Divider()
                        Button("Load sample data") { SampleData.insert(into: context) }
                        #endif
                    } label: {
                        Label("Options", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add item", systemImage: "plus") { addItem() }
                }
            }
            .sheet(item: $newItem) { item in
                ItemEditView(item: item, isNew: true)
            }
            .safeAreaInset(edge: .bottom) {
                if let notice = deletedNotice {
                    UndoBar(message: notice) { undoDelete() } dismiss: { deletedNotice = nil }
                }
            }
        }
    }

    private var list: some View {
        List {
            if !activeItems.isEmpty {
                Section {
                    BurnRateHeader(items: activeItems, mode: costMode, currency: baseCurrency)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section {
                Picker("Cost basis", selection: $costModeRaw) {
                    ForEach(CostMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
            } footer: {
                Text(costMode.explanation)
            }

            Section {
                ForEach(visible) { item in
                    NavigationLink {
                        ItemDetailView(item: item)
                    } label: {
                        ItemRow(
                            item: item,
                            category: catalog.display(for: item.categoryKey),
                            mode: costMode,
                            currency: baseCurrency
                        )
                    }
                }
                .onDelete(perform: delete)
            } header: {
                if let sectorFilter {
                    Text(sectorFilter.label)
                }
            }
        }
    }

    private func addItem() {
        let item = Item(currencyCode: baseCurrency)
        context.insert(item)
        newItem = item
    }

    private func delete(at offsets: IndexSet) {
        let doomed = offsets.compactMap { visible.indices.contains($0) ? visible[$0] : nil }
        guard !doomed.isEmpty else { return }
        let name: String
        if doomed.count == 1 {
            name = doomed[0].name.isEmpty
                ? String(localized: "Item", comment: "Fallback name for an unnamed item")
                : doomed[0].name
        } else {
            name = String(localized: "\(doomed.count) items", comment: "Number of items deleted")
        }

        context.undoManager?.beginUndoGrouping()
        for item in doomed { context.delete(item) }
        context.undoManager?.endUndoGrouping()

        withAnimation {
            deletedNotice = String(localized: "Deleted \(name)", comment: "Undo bar message. The placeholder is an item name or a count.")
        }
    }

    private func undoDelete() {
        context.undoManager?.undo()
        withAnimation { deletedNotice = nil }
    }
}

/// Delete is the one destructive action in the app, so it always comes with a way back.
private struct UndoBar: View {
    let message: String
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Button("Undo", action: undo)
                .font(.subheadline.weight(.semibold))
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .padding(.horizontal, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            // Auto-dismiss so the bar never sits there permanently.
            try? await Task.sleep(for: .seconds(6))
            dismiss()
        }
    }
}

/// The figure the whole application exists to surface: the daily cost of everything owned.
private struct BurnRateHeader: View {
    let items: [Item]
    let mode: CostMode
    let currency: String

    private var perDay: Double {
        items.reduce(0) { $0 + $1.costPerDay(mode: mode) }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Your items cost you")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Money.perDay(perDay, code: currency))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("per day")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(Money.string(perDay * 30.4375, code: currency)) per month · \(Money.string(perDay * 365.25, code: currency)) per year")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
    }
}

private struct EmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No items recorded", systemImage: "square.stack.3d.up.slash")
        } description: {
            Text("Record the items you own — electronics, furniture, appliances, clothing — to see what each one costs you per day.")
        } actions: {
            Button("Add your first item", action: onAdd)
                .buttonStyle(.borderedProminent)
        }
    }
}
