import SwiftUI
import SwiftData

struct ItemListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Item.purchaseDate, order: .reverse) private var items: [Item]
    @Query private var customCategories: [CustomCategory]

    @AppStorage("costMode") private var costModeRaw = CostMode.actual.rawValue
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @AppStorage("heroPeriod") private var periodRaw = CostPeriod.day.rawValue
    @State private var sort: SortOption = .costPerDay
    @State private var showRetired = false
    @State private var sectorFilter: Sector?
    @State private var search = ""
    @State private var newItem: Item?
    @State private var editingItem: Item?
    @State private var retireTrigger = 0

    private var costMode: Binding<CostMode> {
        Binding(get: { CostMode(rawValue: costModeRaw) ?? .actual }, set: { costModeRaw = $0.rawValue })
    }

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

        var symbol: String {
            switch self {
            case .costPerDay: "flame"
            case .price: "banknote"
            case .newest: "calendar"
            case .name: "textformat"
            }
        }
    }

    var body: some View {
        // Everything derived from the items is computed once per render, not once per
        // row or per comparison — sorting by cost alone used to recompute each item's
        // calendar maths O(n log n) times.
        let snapshot = Snapshot(
            items: items,
            catalog: CategoryCatalog(custom: customCategories),
            mode: costMode.wrappedValue,
            sort: sort,
            sector: sectorFilter,
            showRetired: showRetired,
            search: search
        )

        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyStateView(onAdd: { addItem() }, onPickPurchase: pickFromTransactions)
                } else {
                    list(snapshot)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Items")
            .toolbar { toolbar }
            .sheet(item: $newItem) { item in
                ItemEditView(item: item, isNew: true)
            }
            .sheet(item: $editingItem) { item in
                ItemEditView(item: item, isNew: false)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: retireTrigger)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(SortOption.allCases) { option in
                        Label(option.label, systemImage: option.symbol).tag(option)
                    }
                }
                #if DEBUG
                Divider()
                Button("Load sample data", systemImage: "wand.and.stars") { SampleData.insert(into: context) }
                #endif
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .disabled(items.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                DashboardView(embedded: true)
            } label: {
                Label("Insights", systemImage: "chart.bar.xaxis")
            }
            .disabled(items.isEmpty)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Add item", systemImage: "plus") { addItem() }
        }
    }

    private func list(_ snapshot: Snapshot) -> some View {
        List {
            Section {
                BurnRateHero(
                    perDay: snapshot.dailyBurn,
                    activeCount: snapshot.activeCount,
                    currency: baseCurrency,
                    mode: costMode,
                    periodRaw: $periodRaw
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                filters(snapshot)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            Section {
                ForEach(snapshot.rows) { row in
                    NavigationLink {
                        ItemDetailView(item: row.item)
                    } label: {
                        ItemRow(row: row, currency: baseCurrency)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        SwipeDeleteButton { router.pendingDelete = .item(row.item, in: context) }
                        SwipeEditButton { editingItem = row.item }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        retireButton(for: row.item)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editingItem = row.item }
                        retireButton(for: row.item)
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) { router.pendingDelete = .item(row.item, in: context) }
                    } preview: {
                        ItemPreviewCard(row: row, currency: baseCurrency)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .searchable(text: $search, prompt: Text("Search items"))
        .animation(.snappy, value: snapshot.rows.map(\.id))
    }

    @ViewBuilder
    private func filters(_ snapshot: Snapshot) -> some View {
        if snapshot.availableSectors.count > 1 || snapshot.retiredCount > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if snapshot.availableSectors.count > 1 {
                        Chip(title: String(localized: "All sectors"), isSelected: sectorFilter == nil) {
                            withAnimation(.snappy) { sectorFilter = nil }
                        }
                        ForEach(snapshot.availableSectors) { sector in
                            Chip(title: sector.label, systemImage: sector.symbol, isSelected: sectorFilter == sector, tint: sector.tint) {
                                withAnimation(.snappy) { sectorFilter = sectorFilter == sector ? nil : sector }
                            }
                        }
                    }
                    if snapshot.retiredCount > 0 {
                        Chip(
                            title: String(localized: "Show retired"),
                            systemImage: showRetired ? "eye" : "eye.slash",
                            isSelected: showRetired,
                            tint: .gray
                        ) {
                            withAnimation(.snappy) { showRetired.toggle() }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .sensoryFeedback(.selection, trigger: sectorFilter)
            .sensoryFeedback(.selection, trigger: showRetired)
        }
    }

    private func retireButton(for item: Item) -> some View {
        Button {
            withAnimation(.snappy) { item.retiredDate = item.isRetired ? nil : .now }
            retireTrigger += 1
        } label: {
            if item.isRetired {
                Label("Return to service", systemImage: "arrow.uturn.backward")
            } else {
                Label("Retire", systemImage: "archivebox")
            }
        }
        .tint(item.isRetired ? .green : .orange)
    }

    @Environment(AppRouter.self) private var router

    /// Shows the expenses in categories that tend to be things you keep, so a past
    /// purchase can be turned into a tracked item from its context menu or detail.
    private func pickFromTransactions() {
        var filter = TransactionFilter()
        filter.kinds = [.expense]
        filter.categories = Set(RecordCategory.allCases.filter(\.isDurable).map(\.rawValue))
        router.showTransactions(filter)
    }

    private func addItem() {
        let item = Item(currencyCode: baseCurrency)
        context.insert(item)
        newItem = item
    }
}

// MARK: - Derived data

/// One row's worth of precomputed display data.
struct ItemRowModel: Identifiable {
    let item: Item
    let category: CategoryDisplay
    let costPerDay: Double
    let daysOwned: Int
    let progress: Double
    let isPaidOff: Bool
    var id: PersistentIdentifier { item.id }

    init(item: Item, category: CategoryDisplay, mode: CostMode, now: Date) {
        self.item = item
        self.category = category
        let days = item.daysOwned(now: now)
        self.daysOwned = days
        self.costPerDay = mode == .actual ? item.netCost / Double(days) : item.plannedCostPerDay
        self.progress = Double(days) / Double(item.plannedDays)
        self.isPaidOff = days >= item.plannedDays
    }
}

private struct Snapshot {
    let rows: [ItemRowModel]
    let availableSectors: [Sector]
    let dailyBurn: Double
    let activeCount: Int
    let retiredCount: Int

    init(
        items: [Item], catalog: CategoryCatalog, mode: CostMode, sort: ItemListView.SortOption,
        sector: Sector?, showRetired: Bool, search: String
    ) {
        let now = Date.now
        let all = items.map { ItemRowModel(item: $0, category: catalog.display(for: $0.categoryKey), mode: mode, now: now) }

        // The burn rate always reflects everything you still own, regardless of any
        // filter — it's the total you're trying to keep down.
        let active = all.filter { !$0.item.isRetired }
        dailyBurn = active.reduce(0) { $0 + $1.costPerDay }
        activeCount = active.count
        retiredCount = all.count - active.count

        let present = Set(all.map(\.category.sector))
        availableSectors = Sector.allCases.filter { present.contains($0) }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var pool = showRetired ? all : active
        if let sector { pool = pool.filter { $0.category.sector == sector } }
        if !query.isEmpty {
            pool = pool.filter {
                $0.item.name.localizedCaseInsensitiveContains(query)
                    || $0.item.brand.localizedCaseInsensitiveContains(query)
                    || $0.category.label.localizedCaseInsensitiveContains(query)
            }
        }

        switch sort {
        case .costPerDay: pool.sort { $0.costPerDay > $1.costPerDay }
        case .price: pool.sort { $0.item.netCost > $1.item.netCost }
        case .newest: pool.sort { $0.item.purchaseDate > $1.item.purchaseDate }
        case .name: pool.sort { $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending }
        }
        rows = pool
    }
}

// MARK: - Hero

/// The figure the whole application exists to surface: the daily cost of everything
/// owned. Tapping the amount cycles through day, week, month and year.
private struct BurnRateHero: View {
    let perDay: Double
    let activeCount: Int
    let currency: String
    @Binding var mode: CostMode
    @Binding var periodRaw: String

    private var period: CostPeriod { CostPeriod(rawValue: periodRaw) ?? .day }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your items cost you")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))

                Button {
                    withAnimation(.snappy) { periodRaw = period.next.rawValue }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(period.format(perDay, code: currency))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(value: perDay * period.days))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(period.label)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.amber)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: periodRaw)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Your items cost you"))
                .accessibilityValue(Text(verbatim: "\(period.format(perDay, code: currency)) \(period.label)"))
                .accessibilityAction(named: Text("Change period")) { periodRaw = period.next.rawValue }

                Text("\(activeCount) items")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 2)
            }

            CostModePicker(mode: $mode, onDark: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroBackground())
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    let onAdd: () -> Void
    let onPickPurchase: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            BrandMark(size: 96)
                .shadow(color: Brand.leather.opacity(0.35), radius: 24, y: 10)
            VStack(spacing: 8) {
                Text("No items recorded")
                    .font(.title2.bold())
                Text("Record the items you own — electronics, furniture, appliances, clothing — to see what each one costs you per day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Button(action: onAdd) {
                Label("Add your first item", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            Button(action: onPickPurchase) {
                Label("Choose from your transactions", systemImage: "list.bullet.rectangle")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
