import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    /// Pushed from the Items tab rather than owning its own navigation stack.
    var embedded = false

    @Query private var items: [Item]
    @Query private var customCategories: [CustomCategory]
    @AppStorage("costMode") private var costModeRaw = CostMode.actual.rawValue
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault

    private var costMode: Binding<CostMode> {
        Binding(get: { CostMode(rawValue: costModeRaw) ?? .actual }, set: { costModeRaw = $0.rawValue })
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No data to display",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Record a few items and your spending will be summarised here.")
                    )
                } else {
                    // Built once per render. It used to be a computed property, so every
                    // `stats.x` access regrouped and resorted the whole library again.
                    content(Stats(items: items, mode: costMode.wrappedValue, catalog: CategoryCatalog(custom: customCategories)))
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
    }

    private func content(_ stats: Stats) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                CostModePicker(mode: costMode)

                SectorDonutCard(stats: stats, currency: baseCurrency)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(
                        symbol: "sum", tint: Brand.accent,
                        title: String(localized: "Total daily cost", comment: "Statistic label"),
                        value: Money.perDay(stats.dailyBurn, code: baseCurrency),
                        caption: String(localized: "\(Money.string(stats.dailyBurn * 30.4375, code: baseCurrency)) per month · \(Money.string(stats.dailyBurn * 365.25, code: baseCurrency)) per year")
                    )
                    StatTile(
                        symbol: "shippingbox.fill", tint: .blue,
                        title: String(localized: "In service", comment: "Statistic label"),
                        value: "\(stats.activeCount)",
                        caption: String(localized: "\(stats.retiredCount) retired", comment: "Statistic caption")
                    )
                    StatTile(
                        symbol: "tag.fill", tint: .purple,
                        title: String(localized: "Average price", comment: "Statistic label"),
                        value: Money.string(stats.averagePrice, code: baseCurrency),
                        caption: String(localized: "per item", comment: "Statistic caption")
                    )
                    StatTile(
                        symbol: "checkmark.seal.fill", tint: Brand.paidOff,
                        title: String(localized: "Fully amortised", comment: "Statistic label"),
                        value: "\(stats.paidOffCount)",
                        caption: String(localized: "past expected lifetime", comment: "Statistic caption")
                    )
                }

                if !stats.worstValue.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(
                            title: String(localized: "Highest cost per day", comment: "Chart title"),
                            subtitle: String(localized: "Ranked by cost per day, \(costMode.wrappedValue.label)", comment: "Chart subtitle. The placeholder is the selected cost basis.")
                        )
                        VStack(spacing: 4) {
                            ForEach(Array(stats.worstValue.enumerated()), id: \.element.id) { index, entry in
                                NavigationLink {
                                    ItemDetailView(item: entry.item)
                                } label: {
                                    RankedRow(rank: index + 1, entry: entry, maxCost: stats.worstValue[0].costPerDay, currency: baseCurrency)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .card()
                }

                CategoryBarsCard(stats: stats, currency: baseCurrency)

                if stats.byYear.count > 1 {
                    YearChartCard(stats: stats, currency: baseCurrency)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Aggregation

private struct Stats {
    struct Entry: Identifiable {
        let item: Item
        let category: CategoryDisplay
        let costPerDay: Double
        var id: PersistentIdentifier { item.id }
    }

    struct CategorySlice: Identifiable {
        let key: String
        let label: String
        let symbol: String
        let tint: Color
        let total: Double
        var id: String { key }
    }

    struct SectorSlice: Identifiable {
        let sector: Sector
        let total: Double
        var id: String { sector.rawValue }
    }

    struct YearBucket: Identifiable {
        let year: Int
        let total: Double
        var id: Int { year }
    }

    let count: Int
    let activeCount: Int
    let retiredCount: Int
    let totalSpent: Double
    let averagePrice: Double
    let paidOffCount: Int
    /// Only items still in service burn money today.
    let dailyBurn: Double
    let byCategory: [CategorySlice]
    /// Coarser than the category chart — answers "where is my money going" at a glance
    /// once the library spans electronics, furniture, clothes and everything else.
    let bySector: [SectorSlice]
    let byYear: [YearBucket]
    let worstValue: [Entry]

    init(items: [Item], mode: CostMode, catalog: CategoryCatalog) {
        let now = Date.now
        let entries = items.map { item in
            Entry(item: item, category: catalog.display(for: item.categoryKey), costPerDay: item.costPerDay(mode: mode, now: now))
        }
        let active = entries.filter { !$0.item.isRetired }

        count = entries.count
        activeCount = active.count
        retiredCount = count - activeCount
        totalSpent = entries.reduce(0) { $0 + $1.item.priceInBase }
        averagePrice = count == 0 ? 0 : totalSpent / Double(count)
        paidOffCount = active.filter { $0.item.isPaidOff(now: now) }.count
        dailyBurn = active.reduce(0) { $0 + $1.costPerDay }

        byCategory = Dictionary(grouping: entries, by: { $0.category.key })
            .map { key, group in
                let display = group[0].category
                return CategorySlice(
                    key: key, label: display.label, symbol: display.symbol, tint: display.tint,
                    total: group.reduce(0) { $0 + $1.item.priceInBase }
                )
            }
            .sorted { $0.total > $1.total }

        bySector = Dictionary(grouping: entries, by: { $0.category.sector })
            .map { SectorSlice(sector: $0.key, total: $0.value.reduce(0) { $0 + $1.item.priceInBase }) }
            .sorted { $0.total > $1.total }

        let calendar = Calendar.current
        byYear = Dictionary(grouping: entries) { calendar.component(.year, from: $0.item.purchaseDate) }
            .map { YearBucket(year: $0.key, total: $0.value.reduce(0) { $0 + $1.item.priceInBase }) }
            .sorted { $0.year < $1.year }

        worstValue = Array(active.sorted { $0.costPerDay > $1.costPerDay }.prefix(5))
    }
}

// MARK: - Cards

/// Where the money went, by area of life. Tap a slice or a legend entry to focus it.
private struct SectorDonutCard: View {
    let stats: Stats
    let currency: String

    /// Raw touch angles go here, not into view state: only a change of slice updates the card.
    @State private var angleSink = SelectionSink<Double>()
    @State private var selected: Sector?
    /// The slice under the finger during the current gesture; nil between gestures.
    @State private var lastHit: Sector?

    private var focused: Stats.SectorSlice? {
        selected.flatMap { sector in stats.bySector.first { $0.sector == sector } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeader(
                title: String(localized: "Spending by sector", comment: "Chart title"),
                subtitle: String(localized: "Distribution across areas of life", comment: "Chart subtitle")
            )

            Chart(stats.bySector) { slice in
                SectorMark(
                    angle: .value("Spent", slice.total),
                    innerRadius: .ratio(0.64),
                    outerRadius: .ratio(selected == slice.sector ? 1 : 0.92),
                    angularInset: 2
                )
                .cornerRadius(5)
                .foregroundStyle(slice.sector.tint)
                .opacity(selected == nil || selected == slice.sector ? 1 : 0.35)
            }
            .chartAngleSelection(value: angleSink.binding { angle in
                guard let angle else { lastHit = nil; return }
                let hit = sector(at: angle)
                guard hit != lastHit else { return }
                // A fresh tap on the slice that's already focused clears the focus;
                // dragging across slices just moves it.
                let isNewGesture = lastHit == nil
                lastHit = hit
                withAnimation(.snappy) { selected = isNewGesture && selected == hit ? nil : hit }
            })
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let frame = proxy.plotFrame {
                        let rect = geo[frame]
                        VStack(spacing: 2) {
                            if let focused {
                                Image(systemName: focused.sector.symbol)
                                    .font(.title3)
                                    .foregroundStyle(focused.sector.tint)
                                Text(focused.sector.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                Text(Money.string(focused.total, code: currency))
                                    .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                                Text(verbatim: (focused.total / max(stats.totalSpent, 1)).formatted(.percent.precision(.fractionLength(0))))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(focused.sector.tint)
                            } else {
                                Text("Total spent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(Money.string(stats.totalSpent, code: currency))
                                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                Text("\(stats.count) items")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: rect.width * 0.56)
                        .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .frame(height: 230)
            .sensoryFeedback(.selection, trigger: selected)

            FlowLegend(slices: stats.bySector, selected: selected, currency: currency) { sector in
                withAnimation(.snappy) { selected = selected == sector ? nil : sector }
            }
        }
        .card()
    }

    private func sector(at angle: Double) -> Sector? {
        var running = 0.0
        for slice in stats.bySector {
            running += slice.total
            if angle <= running { return slice.sector }
        }
        return stats.bySector.last?.sector
    }
}

private struct FlowLegend: View {
    let slices: [Stats.SectorSlice]
    let selected: Sector?
    let currency: String
    let toggle: (Sector) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(slices) { slice in
                Button { toggle(slice.sector) } label: {
                    HStack(spacing: 8) {
                        Circle().fill(slice.sector.tint).frame(width: 10, height: 10)
                        Text(slice.sector.label)
                            .font(.caption.weight(.medium))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(selected == nil || selected == slice.sector ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(Text(Money.string(slice.total, code: currency)))
                .accessibilityAddTraits(selected == slice.sector ? .isSelected : [])
            }
        }
    }
}

private struct StatTile: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: .rect(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2, reservesSpace: true)
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct RankedRow: View {
    let rank: Int
    let entry: Stats.Entry
    let maxCost: Double
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            CategoryTile(symbol: entry.category.symbol, tint: entry.category.tint, size: 34)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(entry.item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Money.perDay(entry.costPerDay, code: currency))
                        .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                }
                GeometryReader { geo in
                    Capsule()
                        .fill(entry.category.tint.gradient)
                        .frame(width: max(6, geo.size.width * (maxCost > 0 ? entry.costPerDay / maxCost : 0)))
                }
                .frame(height: 5)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

private struct CategoryBarsCard: View {
    let stats: Stats
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(
                title: String(localized: "Spending by category", comment: "Chart title"),
                subtitle: String(localized: "Distribution across categories", comment: "Chart subtitle")
            )
            let maxTotal = max(stats.byCategory.first?.total ?? 1, 1)
            VStack(spacing: 12) {
                ForEach(stats.byCategory) { slice in
                    HStack(spacing: 10) {
                        Image(systemName: slice.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(slice.tint)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(slice.label).font(.caption.weight(.medium)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(Money.string(slice.total, code: currency))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.06))
                                    Capsule()
                                        .fill(slice.tint.gradient)
                                        .frame(width: max(6, geo.size.width * slice.total / maxTotal))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }
}

private struct YearChartCard: View {
    let stats: Stats
    let currency: String

    @State private var selectedYear: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                CardHeader(
                    title: String(localized: "Spending by year", comment: "Chart title"),
                    subtitle: String(localized: "Total committed in each year", comment: "Chart subtitle")
                )
                if let selectedYear, let bucket = stats.byYear.first(where: { String($0.year) == selectedYear }) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Money.string(bucket.total, code: currency))
                            .font(.system(.headline, design: .rounded).monospacedDigit())
                        Text(verbatim: selectedYear)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Chart(stats.byYear) { bucket in
                BarMark(
                    x: .value("Year", String(bucket.year)),
                    y: .value("Spent", bucket.total)
                )
                .cornerRadius(6)
                .foregroundStyle(
                    selectedYear == nil || selectedYear == String(bucket.year)
                        ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary.opacity(0.3))
                )
            }
            .chartXSelection(value: $selectedYear)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Money.string(amount, code: currency)).font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption) }
            }
            .frame(height: 180)
            .sensoryFeedback(.selection, trigger: selectedYear)
        }
        .card()
    }
}
