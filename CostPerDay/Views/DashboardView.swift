import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Query private var gadgets: [Gadget]
    @AppStorage("costMode") private var costModeRaw = CostMode.actual.rawValue
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault

    private var costMode: CostMode { CostMode(rawValue: costModeRaw) ?? .actual }
    private var stats: Stats { Stats(gadgets: gadgets, mode: costMode) }

    var body: some View {
        NavigationStack {
            Group {
                if gadgets.isEmpty {
                    ContentUnavailableView(
                        "Nothing to chart yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Add a few gadgets and your spending shows up here.")
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
                    StatTile(title: "Total spent", value: Money.string(stats.totalSpent, code: baseCurrency), caption: "\(stats.count) gadgets")
                    StatTile(title: "In service", value: "\(stats.activeCount)", caption: "\(stats.retiredCount) retired")
                    StatTile(title: "Average price", value: Money.string(stats.averagePrice, code: baseCurrency), caption: "per gadget")
                    StatTile(title: "Paid off", value: "\(stats.paidOffCount)", caption: "outlived their budget")
                }

                ChartCard(
                    title: "Spend by category",
                    subtitle: "Where the money went"
                ) {
                    Chart(stats.byCategory) { slice in
                        BarMark(
                            x: .value("Spent", slice.total),
                            y: .value("Category", slice.category.label)
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
                        title: "Spend by year",
                        subtitle: "What you committed each year"
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
                        title: "Worst value per day",
                        subtitle: "Your most expensive habits, \(costMode.label.lowercased())"
                    ) {
                        VStack(spacing: 0) {
                            ForEach(Array(stats.worstValue.enumerated()), id: \.element.id) { index, gadget in
                                if index > 0 { Divider() }
                                NavigationLink {
                                    GadgetDetailView(gadget: gadget)
                                } label: {
                                    WorstValueRow(gadget: gadget, mode: costMode, currency: baseCurrency)
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
    let gadgets: [Gadget]
    let mode: CostMode

    var active: [Gadget] { gadgets.filter { !$0.isRetired } }
    var count: Int { gadgets.count }
    var activeCount: Int { active.count }
    var retiredCount: Int { count - activeCount }
    var totalSpent: Double { gadgets.reduce(0) { $0 + $1.priceInBase } }
    var averagePrice: Double { count == 0 ? 0 : totalSpent / Double(count) }
    var paidOffCount: Int { active.filter { $0.isPaidOff() }.count }

    /// Only items still in service burn money today.
    var dailyBurn: Double { active.reduce(0) { $0 + $1.costPerDay(mode: mode) } }

    struct CategorySlice: Identifiable {
        let category: GadgetCategory
        let total: Double
        var id: String { category.rawValue }
    }

    var byCategory: [CategorySlice] {
        Dictionary(grouping: gadgets, by: \.category)
            .map { CategorySlice(category: $0.key, total: $0.value.reduce(0) { $0 + $1.priceInBase }) }
            .sorted { $0.total > $1.total }
    }

    var maxCategoryTotal: Double { max(1, byCategory.first?.total ?? 1) }

    struct YearBucket: Identifiable {
        let year: Int
        let total: Double
        var id: Int { year }
    }

    var byYear: [YearBucket] {
        Dictionary(grouping: gadgets) { Calendar.current.component(.year, from: $0.purchaseDate) }
            .map { YearBucket(year: $0.key, total: $0.value.reduce(0) { $0 + $1.priceInBase }) }
            .sorted { $0.year < $1.year }
    }

    var worstValue: [Gadget] {
        active.sorted { $0.costPerDay(mode: mode) > $1.costPerDay(mode: mode) }.prefix(5).map { $0 }
    }
}

// MARK: - Pieces

private struct HeroBurnRate: View {
    let perDay: Double
    let currency: String

    var body: some View {
        VStack(spacing: 4) {
            Text("Daily burn rate")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(Money.perDay(perDay, code: currency))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("\(Money.string(perDay * 30.4375, code: currency)) / month · \(Money.string(perDay * 365.25, code: currency)) / year")
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
    let gadget: Gadget
    let mode: CostMode
    let currency: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: gadget.category.symbol)
                .foregroundStyle(gadget.category.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(gadget.name.isEmpty ? "Untitled" : gadget.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Text("\(Money.string(gadget.price, code: gadget.currencyCode)) · \(Duration.fromDays(gadget.daysOwned())) owned")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(Money.perDay(gadget.costPerDay(mode: mode), code: currency))
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }
}
