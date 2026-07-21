import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query private var items: [Item]
    @Query private var customCategories: [CustomCategory]
    @AppStorage("costMode") private var costModeRaw = CostMode.actual.rawValue
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault

    private var costMode: CostMode { CostMode(rawValue: costModeRaw) ?? .actual }
    private var stats: Stats { Stats(items: items, mode: costMode, catalog: CategoryCatalog(custom: customCategories)) }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No data to display",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Record a few items and your spending will be summarised here.")
                    )
                } else {
                    content
                }
            }
            .navigationTitle("Dashboard")
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                Picker("Cost basis", selection: $costModeRaw) {
                    ForEach(CostMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)

                HeroBurnRate(perDay: stats.dailyBurn, currency: baseCurrency)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: String(localized: "Total spent", comment: "Statistic label"), value: Money.string(stats.totalSpent, code: baseCurrency), caption: String(localized: "\(stats.count) items", comment: "Statistic caption"))
                    StatTile(title: String(localized: "In service", comment: "Statistic label"), value: "\(stats.activeCount)", caption: String(localized: "\(stats.retiredCount) retired", comment: "Statistic caption"))
                    StatTile(title: String(localized: "Average price", comment: "Statistic label"), value: Money.string(stats.averagePrice, code: baseCurrency), caption: String(localized: "per item", comment: "Statistic caption"))
                    StatTile(title: String(localized: "Fully amortised", comment: "Statistic label"), value: "\(stats.paidOffCount)", caption: String(localized: "past expected lifetime", comment: "Statistic caption"))
                }

                if stats.bySector.count > 1 {
                    ChartCard(
                        title: String(localized: "Spending by sector", comment: "Chart title"),
                        subtitle: String(localized: "Distribution across areas of life", comment: "Chart subtitle")
                    ) {
                        Chart(stats.bySector) { slice in
                            BarMark(
                                x: .value("Spent", slice.total),
                                y: .value("Sector", slice.sector.label)
                            )
                            .cornerRadius(4)
                            .foregroundStyle(Color.accentColor)
                            .annotation(position: .trailing, alignment: .leading) {
                                Text(Money.string(slice.total, code: baseCurrency))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(preset: .aligned, position: .leading) { _ in
                                AxisValueLabel().font(.caption)
                            }
                        }
                        .chartXScale(domain: 0...(stats.maxSectorTotal * 1.28))
                        .frame(height: CGFloat(stats.bySector.count) * 32 + 20)
                    }
                }

                ChartCard(
                    title: String(localized: "Spending by category", comment: "Chart title"),
                    subtitle: String(localized: "Distribution across categories", comment: "Chart subtitle")
                ) {
                    Chart(stats.byCategory) { slice in
                        BarMark(
                            x: .value("Spent", slice.total),
                            y: .value("Category", slice.label)
                        )
                        .cornerRadius(4)
                        .foregroundStyle(Color.accentColor)
                        .annotation(position: .trailing, alignment: .leading) {
                            Text(Money.string(slice.total, code: baseCurrency))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(preset: .aligned, position: .leading) { _ in
                            AxisValueLabel().font(.caption)
                        }
                    }
                    .chartXScale(domain: 0...(stats.maxCategoryTotal * 1.28))
                    .frame(height: CGFloat(stats.byCategory.count) * 30 + 20)
                }

                if stats.byYear.count > 1 {
                    ChartCard(
                        title: String(localized: "Spending by year", comment: "Chart title"),
                        subtitle: String(localized: "Total committed in each year", comment: "Chart subtitle")
                    ) {
                        Chart(stats.byYear) { bucket in
                            BarMark(
                                x: .value("Year", String(bucket.year)),
                                y: .value("Spent", bucket.total)
                            )
                            .cornerRadius(4)
                            .foregroundStyle(Color.accentColor)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine().foregroundStyle(.quaternary)
                                AxisValueLabel {
                                    if let amount = value.as(Double.self) {
                                        Text(Money.string(amount, code: baseCurrency)).font(.caption2)
                                    }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in AxisValueLabel().font(.caption) }
                        }
                        .frame(height: 180)
                    }
                }

                if !stats.worstValue.isEmpty {
                    ChartCard(
                        title: String(localized: "Highest cost per day", comment: "Chart title"),
                        subtitle: String(localized: "Ranked by cost per day, \(costMode.label)", comment: "Chart subtitle. The placeholder is the selected cost basis.")
                    ) {
                        VStack(spacing: 0) {
                            ForEach(Array(stats.worstValue.enumerated()), id: \.element.item.id) { index, entry in
                                if index > 0 { Divider() }
                                NavigationLink {
                                    ItemDetailView(item: entry.item)
                                } label: {
                                    WorstValueRow(entry: entry, mode: costMode, currency: baseCurrency)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Aggregation

private struct Stats {
    let items: [Item]
    let mode: CostMode
    let catalog: CategoryCatalog

    struct Entry: Identifiable {
        let item: Item
        let category: CategoryDisplay
        var id: PersistentIdentifier { item.id }
    }

    var entries: [Entry] { items.map { Entry(item: $0, category: catalog.display(for: $0.categoryKey)) } }
    var active: [Item] { items.filter { !$0.isRetired } }
    var count: Int { items.count }
    var activeCount: Int { active.count }
    var retiredCount: Int { count - activeCount }
    var totalSpent: Double { items.reduce(0) { $0 + $1.priceInBase } }
    var averagePrice: Double { count == 0 ? 0 : totalSpent / Double(count) }
    var paidOffCount: Int { active.filter { $0.isPaidOff() }.count }

    /// Only items still in service burn money today.
    var dailyBurn: Double { active.reduce(0) { $0 + $1.costPerDay(mode: mode) } }

    struct CategorySlice: Identifiable {
        let key: String
        let label: String
        let total: Double
        var id: String { key }
    }

    var byCategory: [CategorySlice] {
        Dictionary(grouping: entries, by: { $0.category.key })
            .map { key, group in
                CategorySlice(
                    key: key,
                    label: group[0].category.label,
                    total: group.reduce(0) { $0 + $1.item.priceInBase }
                )
            }
            .sorted { $0.total > $1.total }
    }

    struct SectorSlice: Identifiable {
        let sector: Sector
        let total: Double
        var id: String { sector.rawValue }
    }

    /// Coarser than the category chart — answers "where is my money going" at a glance
    /// once the library spans electronics, furniture, clothes and everything else.
    var bySector: [SectorSlice] {
        Dictionary(grouping: entries, by: { $0.category.sector })
            .map { SectorSlice(sector: $0.key, total: $0.value.reduce(0) { $0 + $1.item.priceInBase }) }
            .sorted { $0.total > $1.total }
    }

    var maxCategoryTotal: Double { max(1, byCategory.first?.total ?? 1) }
    var maxSectorTotal: Double { max(1, bySector.first?.total ?? 1) }

    struct YearBucket: Identifiable {
        let year: Int
        let total: Double
        var id: Int { year }
    }

    var byYear: [YearBucket] {
        Dictionary(grouping: items) { Calendar.current.component(.year, from: $0.purchaseDate) }
            .map { YearBucket(year: $0.key, total: $0.value.reduce(0) { $0 + $1.priceInBase }) }
            .sorted { $0.year < $1.year }
    }

    var worstValue: [Entry] {
        entries
            .filter { !$0.item.isRetired }
            .sorted { $0.item.costPerDay(mode: mode) > $1.item.costPerDay(mode: mode) }
            .prefix(5)
            .map { $0 }
    }
}

// MARK: - Pieces

private struct HeroBurnRate: View {
    let perDay: Double
    let currency: String

    var body: some View {
        VStack(spacing: 4) {
            Text("Total daily cost")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Money.perDay(perDay, code: currency))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("\(Money.string(perDay * 30.4375, code: currency)) per month · \(Money.string(perDay * 365.25, code: currency)) per year")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
    }
}

private struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

private struct WorstValueRow: View {
    let entry: Stats.Entry
    let mode: CostMode
    let currency: String

    private var item: Item { entry.item }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.category.symbol)
                .foregroundStyle(entry.category.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name.isEmpty ? String(localized: "Untitled", comment: "Fallback name for an unnamed item") : item.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(String(localized: "\(Money.string(item.price, code: item.currencyCode)) · \(Duration.fromDays(item.daysOwned())) owned", comment: "Row subtitle. First placeholder is a price, second a duration."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(Money.perDay(item.costPerDay(mode: mode), code: currency))
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}
