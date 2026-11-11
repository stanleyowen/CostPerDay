import SwiftUI
import SwiftData
import Charts

/// Detailed reports for any week, month, quarter, year or all time — with drill-down
/// from any category to its trend and transactions.
struct ReportsView: View {
    @Query(sort: \Record.date, order: .reverse) private var records: [Record]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @AppStorage("reportRange") private var rangeRaw = ReportRange.month.rawValue

    @State private var anchor = Date.now
    @State private var accountFilter: UUID?
    @State private var breakdownByGroup = true
    @State private var exportURL: URL?

    private var range: ReportRange { ReportRange(rawValue: rangeRaw) ?? .month }

    var body: some View {
        let ledger = LedgerSnapshot(accounts: accounts, records: records, baseCurrency: baseCurrency)
        let earliest = ledger.flows.last?.date
        let period = ReportPeriod.containing(anchor, range: range, earliest: earliest)
        let report = Report.build(flows: ledger.flows, period: period, excludedAccounts: ledger.excludedFromStats, accountFilter: accountFilter)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    rangePicker
                    periodNavigator(period: period, earliest: earliest)

                    if records.isEmpty {
                        ContentUnavailableView("No data yet", systemImage: "chart.pie", description: Text("Reports appear once you've recorded some transactions."))
                            .padding(.top, 40)
                    } else {
                        SummaryCard(report: report, currency: baseCurrency)
                        if report.transactionCount > 0 {
                            CashFlowChartCard(report: report, currency: baseCurrency)
                            BreakdownCard(report: report, ledger: ledger, records: records, currency: baseCurrency, byGroup: $breakdownByGroup, accountFilter: accountFilter)
                            if !report.incomeByCategory.isEmpty {
                                IncomeCard(report: report, currency: baseCurrency)
                            }
                            if range == .month {
                                CalendarHeatmapCard(report: report, currency: baseCurrency)
                            } else if range != .week {
                                WeekdayCard(report: report, currency: baseCurrency)
                            }
                            NetWorthTrendCard(ledger: ledger, period: period, currency: baseCurrency)
                            TopExpensesCard(report: report, ledger: ledger, records: records, currency: baseCurrency)
                            if !report.byLabel.isEmpty {
                                LabelsCard(report: report, currency: baseCurrency)
                            }
                            if accountFilter == nil, report.expenseByAccount.count > 1 {
                                AccountsBreakdownCard(report: report, ledger: ledger, currency: baseCurrency)
                            }
                            InsightsCard(report: report, currency: baseCurrency)
                        } else {
                            ContentUnavailableView("Nothing in this period", systemImage: "calendar.badge.exclamationmark", description: Text("Try an earlier period or a longer range."))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(.snappy, value: period)
            }
            .defaultScrollAnchor(DebugFlags.scrollAnchor)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Account", selection: $accountFilter) {
                            Text("All accounts").tag(UUID?.none)
                            ForEach(ledger.activeAccounts) { account in
                                Label(account.displayName, systemImage: account.kind.symbol).tag(UUID?.some(account.uuid))
                            }
                        }
                    } label: {
                        Label(ledger.account(accountFilter)?.displayName ?? String(localized: "All accounts"), systemImage: accountFilter == nil ? "building.columns" : "building.columns.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.medium))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportURL = try? TransactionExport.writeCSV(records: records.filter { period.contains($0.date) }, accounts: accounts, baseCurrency: baseCurrency, title: period.title)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("Export CSV"))
                    .disabled(report.transactionCount == 0)
                }
            }
            .sheet(item: $exportURL) { ShareSheet(url: $0) }
            .navigationDestination(for: Record.self) { RecordDetailView(record: $0) }
            .navigationDestination(for: CategoryReportRoute.self) { route in
                CategoryReportView(route: route, records: records, accounts: accounts)
            }
        }
    }

    private var rangePicker: some View {
        Picker("Range", selection: Binding(get: { range }, set: { rangeRaw = $0.rawValue; anchor = .now })) {
            ForEach(ReportRange.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: rangeRaw)
    }

    private func periodNavigator(period: ReportPeriod, earliest: Date?) -> some View {
        let canGoBack = range != .all && (earliest.map { period.interval.start > $0 } ?? false)
        let canGoForward = range != .all && period.interval.end <= Date.now
        return HStack {
            Button {
                withAnimation(.snappy) { anchor = period.shifted(by: -1).interval.start }
            } label: {
                Image(systemName: "chevron.left").font(.body.weight(.semibold)).frame(width: 40, height: 36)
            }
            .disabled(!canGoBack)
            .accessibilityLabel(Text("Previous period"))
            Spacer()
            VStack(spacing: 1) {
                Text(period.title)
                    .font(.headline)
                    .contentTransition(.opacity)
                if period.contains(.now) && range != .all {
                    Text("Current").font(.caption2.weight(.semibold)).foregroundStyle(.tint)
                }
            }
            .onTapGesture { withAnimation(.snappy) { anchor = .now } }
            Spacer()
            Button {
                withAnimation(.snappy) { anchor = period.shifted(by: 1).interval.start }
            } label: {
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).frame(width: 40, height: 36)
            }
            .disabled(!canGoForward)
            .accessibilityLabel(Text("Next period"))
        }
        .sensoryFeedback(.selection, trigger: anchor)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0, canGoForward { withAnimation(.snappy) { anchor = period.shifted(by: 1).interval.start } }
                if value.translation.width > 0, canGoBack { withAnimation(.snappy) { anchor = period.shifted(by: -1).interval.start } }
            }
        )
    }
}

// MARK: - Summary

private struct SummaryCard: View {
    let report: Report
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Text(Money.string(report.expense, code: currency))
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(value: report.expense))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .sensitive()
                }
                Spacer()
                if let change = report.expenseChange {
                    VStack(alignment: .trailing, spacing: 3) {
                        ChangeBadge(change: change)
                        Text("vs previous").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            HStack {
                FigureColumn(title: String(localized: "Income"), value: Money.string(report.income, code: currency), tint: .income)
                Spacer()
                FigureColumn(title: String(localized: "Net"), value: Money.string(report.net, code: currency), tint: report.net >= 0 ? .income : Brand.ember, alignment: .center)
                Spacer()
                FigureColumn(title: String(localized: "Saved"), value: report.savingsRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—", alignment: .trailing)
            }
        }
        .card()
    }
}

// MARK: - Cash flow

private struct CashFlowChartCard: View {
    let report: Report
    let currency: String
    @State private var selected: Date?
    /// Spending alone by default: one payday would otherwise flatten every daily
    /// expense into the baseline.
    @AppStorage("cashFlowShowsIncome") private var showsIncome = false

    private var unit: Calendar.Component {
        guard report.buckets.count > 1, let first = report.buckets.first else { return .day }
        let span = first.end.timeIntervalSince(first.start)
        if span > 86_400 * 300 { return .year }
        if span > 86_400 * 27 { return .month }
        if span > 86_400 * 6 { return .weekOfYear }
        return .day
    }

    var body: some View {
        let focused = selected.flatMap { date in report.buckets.first { date >= $0.start && date < $0.end } }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                CardHeader(
                    title: showsIncome ? String(localized: "Cash flow", comment: "Chart title") : String(localized: "Spending", comment: "Chart title"),
                    subtitle: showsIncome ? String(localized: "Income and spending over time", comment: "Chart subtitle") : String(localized: "Spending over time", comment: "Chart subtitle")
                )
                if let focused {
                    VStack(alignment: .trailing, spacing: 1) {
                        if showsIncome {
                            Text(verbatim: "+\(Money.string(focused.income, code: currency))").foregroundStyle(Color.income)
                        }
                        Text(verbatim: "−\(Money.string(focused.expense, code: currency))").foregroundStyle(Brand.ember)
                        Text(label(for: focused.start)).foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.semibold).monospacedDigit())
                }
            }
            Chart {
                ForEach(report.buckets) { bucket in
                    if showsIncome {
                        BarMark(x: .value("Period", bucket.start, unit: unit), y: .value("Amount", bucket.income))
                            .foregroundStyle(Color.income.gradient)
                            .cornerRadius(3)
                            .opacity(focused == nil || focused?.start == bucket.start ? 1 : 0.35)
                    }
                    BarMark(x: .value("Period", bucket.start, unit: unit), y: .value("Amount", showsIncome ? -bucket.expense : bucket.expense))
                        .foregroundStyle(Brand.ember.gradient)
                        .cornerRadius(3)
                        .opacity(focused == nil || focused?.start == bucket.start ? 1 : 0.35)
                }
                if showsIncome {
                    RuleMark(y: .value("Zero", 0)).foregroundStyle(.quaternary)
                } else if report.averageDailyExpense > 0, unit == .day {
                    RuleMark(y: .value("Average", report.averageDailyExpense))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("avg \(Money.compact(report.averageDailyExpense, code: currency))")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Money.compact(abs(v), code: currency)).font(.caption2) }
                    }
                }
            }
            .frame(height: 200)
            .sensoryFeedback(.selection, trigger: focused?.start)
            .sensitive()
            Picker("Show", selection: $showsIncome.animation(.snappy)) {
                Text("Spending").tag(false)
                Text("Income & spending").tag(true)
            }
            .pickerStyle(.segmented)
        }
        .card()
    }

    private func label(for date: Date) -> String {
        switch unit {
        case .day: date.formatted(.dateTime.day().month(.abbreviated))
        case .weekOfYear: date.formatted(.dateTime.day().month(.abbreviated))
        case .month: date.formatted(.dateTime.month(.abbreviated).year())
        default: date.formatted(.dateTime.year())
        }
    }
}

// MARK: - Breakdown

struct CategoryReportRoute: Hashable {
    /// A category key, or `group:<raw>`.
    let key: String
    let period: ReportPeriod
    let accountFilter: UUID?

    var display: RecordCategoryDisplay {
        if key.hasPrefix("group:"), let group = RecordGroup(rawValue: String(key.dropFirst(6))) {
            return RecordCategoryDisplay(key: key, label: group.label, symbol: group.symbol, tint: group.tint, group: group, isMissing: false)
        }
        return RecordCategoryDisplay.resolve(key)
    }
}

private struct BreakdownCard: View {
    let report: Report
    let ledger: LedgerSnapshot
    let records: [Record]
    let currency: String
    @Binding var byGroup: Bool
    let accountFilter: UUID?

    var body: some View {
        let slices = byGroup ? report.expenseByGroup : report.expenseByCategory
        let maxTotal = max(slices.first?.total ?? 1, 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardHeader(title: String(localized: "Where it went", comment: "Chart title"))
                Picker("Breakdown", selection: $byGroup) {
                    Text("Groups").tag(true)
                    Text("Categories").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
            }

            Chart(slices.prefix(8)) { slice in
                SectorMark(angle: .value("Spent", slice.total), innerRadius: .ratio(0.6), angularInset: 1.2)
                    .cornerRadius(3)
                    .foregroundStyle(display(slice.key).tint)
            }
            .frame(height: 170)
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let frame = proxy.plotFrame {
                        let rect = geo[frame]
                        VStack(spacing: 0) {
                            Text("\(report.expenseCount) expenses").font(.caption2).foregroundStyle(.secondary)
                            Text(Money.compact(report.expense, code: currency))
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .sensitive()
                        }
                        .position(x: rect.midX, y: rect.midY)
                    }
                }
            }

            VStack(spacing: 2) {
                ForEach(slices) { slice in
                    let display = display(slice.key)
                    NavigationLink(value: CategoryReportRoute(key: byGroup ? "group:" + slice.key : slice.key, period: report.period, accountFilter: accountFilter)) {
                        HStack(spacing: 10) {
                            CategoryTile(symbol: display.symbol, tint: display.tint, size: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(display.label).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Spacer(minLength: 6)
                                    Text(Money.string(slice.total, code: currency))
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .sensitive()
                                }
                                HStack(spacing: 8) {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.primary.opacity(0.06))
                                            Capsule().fill(display.tint.gradient).frame(width: max(5, geo.size.width * slice.total / maxTotal))
                                        }
                                    }
                                    .frame(height: 5)
                                    Text((slice.total / max(report.expense, 0.01)).formatted(.percent.precision(.fractionLength(0))))
                                        .font(.caption2.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 36, alignment: .trailing)
                                }
                            }
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
        .animation(.snappy, value: byGroup)
    }

    private func display(_ key: String) -> RecordCategoryDisplay {
        if byGroup, let group = RecordGroup(rawValue: key) {
            return RecordCategoryDisplay(key: key, label: group.label, symbol: group.symbol, tint: group.tint, group: group, isMissing: false)
        }
        return RecordCategoryDisplay.resolve(key)
    }
}

private struct IncomeCard: View {
    let report: Report
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: String(localized: "Income sources", comment: "Chart title"), subtitle: String(localized: "\(report.incomeCount) transactions", comment: "Chart subtitle"))
            ForEach(report.incomeByCategory.prefix(6)) { slice in
                let display = RecordCategoryDisplay.resolve(slice.key)
                HStack(spacing: 10) {
                    CategoryTile(symbol: display.symbol, tint: display.tint, size: 30)
                    Text(display.label).font(.subheadline).lineLimit(1)
                    Spacer()
                    Text(Money.string(slice.total, code: currency))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.income)
                        .sensitive()
                }
            }
        }
        .card()
    }
}

// MARK: - Calendar & weekday

private struct CalendarHeatmapCard: View {
    let report: Report
    let currency: String
    @State private var selectedDay: Date?

    var body: some View {
        let calendar = Calendar.current
        let start = report.period.interval.start
        let days = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let maxDay = max(report.dailyExpense.values.max() ?? 1, 1)
        let symbols = Array(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1)...] + calendar.veryShortStandaloneWeekdaySymbols[..<(calendar.firstWeekday - 1)])
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                CardHeader(title: String(localized: "Spending calendar", comment: "Chart title"), subtitle: String(localized: "Darker days cost more", comment: "Chart subtitle"))
                if let selectedDay {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Money.string(report.dailyExpense[selectedDay] ?? 0, code: currency))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        Text(selectedDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            LazyVGrid(columns: columns, spacing: 5) {
                // Distinct ID spaces: all three ForEach share one grid, and overlapping
                // integer IDs make SwiftUI silently drop cells.
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
                ForEach((0..<leading).map { -1 - $0 - 7 }, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach((0..<days).map { 100 + $0 }, id: \.self) { cell in
                    let offset = cell - 100
                    let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
                    let value = report.dailyExpense[day] ?? 0
                    let intensity = value / maxDay
                    let isFuture = day > Date.now
                    Button {
                        withAnimation(.snappy) { selectedDay = selectedDay == day ? nil : day }
                    } label: {
                        Text("\(offset + 1)")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(intensity > 0.55 ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                value > 0 ? AnyShapeStyle(Brand.ember.opacity(0.15 + 0.85 * intensity)) : AnyShapeStyle(Color.primary.opacity(isFuture ? 0.02 : 0.05)),
                                in: .rect(cornerRadius: 8, style: .continuous)
                            )
                            .overlay {
                                if selectedDay == day {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary, lineWidth: 1.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isFuture)
                    .accessibilityLabel(Text(day.formatted(date: .abbreviated, time: .omitted)))
                    .accessibilityValue(Text(Money.string(value, code: currency)))
                }
            }
            .sensoryFeedback(.selection, trigger: selectedDay)
        }
        .card()
    }
}

private struct WeekdayCard: View {
    let report: Report
    let currency: String

    var body: some View {
        let calendar = Calendar.current
        let order = (0..<7).map { ($0 + calendar.firstWeekday - 1) % 7 }
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let peak = report.weekdayExpense.max() ?? 0
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: String(localized: "By day of week", comment: "Chart title"), subtitle: String(localized: "Average spending per day", comment: "Chart subtitle"))
            Chart(order, id: \.self) { index in
                BarMark(x: .value("Day", symbols[index]), y: .value("Average", report.weekdayExpense[index]))
                    .foregroundStyle(report.weekdayExpense[index] == peak && peak > 0 ? AnyShapeStyle(Brand.flame) : AnyShapeStyle(Color.secondary.opacity(0.35)))
                    .cornerRadius(5)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { if let v = value.as(Double.self) { Text(Money.compact(v, code: currency)).font(.caption2) } }
                }
            }
            .frame(height: 150)
            .sensitive()
        }
        .card()
    }
}

// MARK: - Net worth

private struct NetWorthTrendCard: View {
    let ledger: LedgerSnapshot
    let period: ReportPeriod
    let currency: String
    @State private var selected: Date?

    var body: some View {
        let buckets = period.buckets().filter { $0.start <= Date.now }
        let series = Ledger.netWorthSeries(accounts: ledger.refs, flows: ledger.flows, rates: ledger.rates, buckets: buckets)
        let chart = TrendChart(series: series, currency: currency, selection: $selected)
        if series.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    CardHeader(title: String(localized: "Balance trend", comment: "Chart title"), subtitle: String(localized: "All accounts, at the end of each period", comment: "Chart subtitle"))
                    if let focused = chart.focused {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Money.string(focused.value, code: currency)).font(.subheadline.weight(.bold).monospacedDigit())
                            Text(focused.date.formatted(.dateTime.day().month(.abbreviated).year())).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                chart
                    .frame(height: 170)
                    .sensitive()
            }
            .card()
        }
    }
}

// MARK: - Lists

private struct TopExpensesCard: View {
    let report: Report
    let ledger: LedgerSnapshot
    let records: [Record]
    let currency: String

    var body: some View {
        let ids = Set(report.largestExpenses.map(\.id))
        let byID = Dictionary(records.lazy.filter { ids.contains($0.uuid) }.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: String(localized: "Largest expenses", comment: "Chart title"))
                .padding(.bottom, 4)
            ForEach(report.largestExpenses) { flow in
                if let record = byID[flow.id] {
                    NavigationLink(value: record) {
                        RecordRow(flow: flow, accountLine: ledger.accountLine(for: flow), showsDate: true, linkedItemName: record.item?.displayName)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }
}

private struct LabelsCard: View {
    let report: Report
    let currency: String
    @Environment(AppRouter.self) private var router

    var body: some View {
        let maxTotal = max(report.byLabel.first?.total ?? 1, 1)
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: String(localized: "By label", comment: "Chart title"), subtitle: String(localized: "Spending tagged with each label", comment: "Chart subtitle"))
            ForEach(report.byLabel.prefix(8)) { slice in
                Button {
                    var filter = TransactionFilter()
                    filter.labels = [slice.key]
                    router.showTransactions(filter)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(slice.key).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            Text(verbatim: "\(slice.count)×").font(.caption).foregroundStyle(.tertiary)
                            Spacer()
                            Text(Money.string(slice.total, code: currency)).font(.subheadline.weight(.semibold).monospacedDigit()).sensitive()
                        }
                        GeometryReader { geo in
                            Capsule().fill(LabelTint.color(for: slice.key).gradient).frame(width: max(5, geo.size.width * slice.total / maxTotal))
                        }
                        .frame(height: 5)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }
}

private struct AccountsBreakdownCard: View {
    let report: Report
    let ledger: LedgerSnapshot
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: String(localized: "Spending by account", comment: "Chart title"))
            Chart(report.expenseByAccount.prefix(6)) { slice in
                let account = UUID(uuidString: slice.key).flatMap(ledger.account)
                BarMark(x: .value("Spent", slice.total), y: .value("Account", account?.displayName ?? "—"))
                    .foregroundStyle((account?.tint.color ?? .gray).gradient)
                    .cornerRadius(5)
                    .annotation(position: .trailing) {
                        Text(Money.compact(slice.total, code: currency)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(min(report.expenseByAccount.count, 6)) * 34 + 10)
            .sensitive()
        }
        .card()
    }
}

private struct InsightsCard: View {
    let report: Report
    let currency: String

    var body: some View {
        let biggestDay = report.dailyExpense.max { $0.value < $1.value }
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: String(localized: "Insights", comment: "Card title")).padding(.bottom, 6)
            InfoRow("Average per day", value: Money.string(report.averageDailyExpense, code: currency))
            Divider()
            InfoRow("Average per expense", value: Money.string(report.expenseCount > 0 ? report.expense / Double(report.expenseCount) : 0, code: currency))
            Divider()
            InfoRow("Transactions", value: "\(report.transactionCount)")
            if let biggestDay {
                Divider()
                InfoRow("Most expensive day", value: "\(biggestDay.key.formatted(.dateTime.day().month(.abbreviated))) · \(Money.string(biggestDay.value, code: currency))")
            }
            if let top = report.expenseByCategory.first {
                Divider()
                InfoRow("Top category", value: RecordCategoryDisplay.resolve(top.key).label)
            }
        }
        .card()
    }
}

// MARK: - Category drill-down

/// One category or group: its 12-period trend, sub-categories and transactions.
struct CategoryReportView: View {
    let route: CategoryReportRoute
    let records: [Record]
    let accounts: [Account]

    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @Environment(AppRouter.self) private var router

    private func matches(_ flow: Flow) -> Bool {
        guard flow.kind != .transfer else { return false }
        if let account = route.accountFilter, flow.accountID != account { return false }
        if route.key.hasPrefix("group:") { return "group:" + flow.category.group.rawValue == route.key }
        return flow.categoryKey == route.key
    }

    var body: some View {
        let display = route.display
        let ledger = LedgerSnapshot(accounts: accounts, records: [], baseCurrency: baseCurrency)
        let excluded = Set(accounts.filter(\.excludeFromStats).map(\.uuid))
        let matching = records.filter { record in
            let flow = record.flow
            if let id = flow.accountID, excluded.contains(id) { return false }
            return matches(flow)
        }
        let inPeriod = matching.filter { route.period.contains($0.date) }
        let flows = matching.map(\.flow)
        let total = inPeriod.reduce(0) { $0 + $1.flow.baseAmount }
        let trend = trendSeries(flows: flows)
        let subcategories = Dictionary(grouping: inPeriod.map(\.flow), by: \.categoryKey)
            .map { (key: $0.key, total: $0.value.reduce(0) { $0 + $1.baseAmount }) }
            .sorted { $0.total > $1.total }

        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        CategoryTile(symbol: display.symbol, tint: display.tint, size: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(route.period.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            Text(Money.string(total, code: baseCurrency))
                                .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                                .sensitive()
                        }
                        Spacer()
                        Text(verbatim: "\(inPeriod.count)×").font(.headline).foregroundStyle(.secondary)
                    }
                    if trend.count > 1 {
                        Chart(trend, id: \.start) { bucket in
                            BarMark(x: .value("Period", bucket.start, unit: trendUnit), y: .value("Spent", bucket.total))
                                .foregroundStyle(route.period.contains(bucket.start) ? AnyShapeStyle(display.tint.gradient) : AnyShapeStyle(display.tint.opacity(0.3)))
                                .cornerRadius(4)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                                AxisGridLine().foregroundStyle(.quaternary)
                                AxisValueLabel { if let v = value.as(Double.self) { Text(Money.compact(v, code: baseCurrency)).font(.caption2) } }
                            }
                        }
                        .frame(height: 140)
                        .sensitive()
                    }
                }
                .padding(.vertical, 6)
            }

            if route.key.hasPrefix("group:"), subcategories.count > 1 {
                Section("Categories") {
                    ForEach(subcategories, id: \.key) { entry in
                        let sub = RecordCategoryDisplay.resolve(entry.key)
                        HStack(spacing: 10) {
                            CategoryTile(symbol: sub.symbol, tint: sub.tint, size: 30)
                            Text(sub.label)
                            Spacer()
                            Text(Money.string(entry.total, code: baseCurrency)).monospacedDigit().foregroundStyle(.secondary).sensitive()
                        }
                    }
                }
            }

            Section("Transactions") {
                ForEach(inPeriod.prefix(300)) { record in
                    NavigationLink(value: record) {
                        RecordRow(flow: record.flow, accountLine: ledger.accountLine(for: record.flow), showsDate: true, linkedItemName: record.item?.displayName)
                    }
                }
            }
        }
        .navigationTitle(display.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Show in Transactions", systemImage: "list.bullet") {
                var filter = TransactionFilter()
                filter.categories = [route.key]
                if let account = route.accountFilter { filter.accounts = [account] }
                router.showTransactions(filter)
            }
        }
    }

    private var trendUnit: Calendar.Component {
        switch route.period.range {
        case .week: .weekOfYear
        case .month, .quarter: .month
        case .year, .all: .year
        }
    }

    /// The selected period and the eleven before it, so the bar for "now" has context.
    private func trendSeries(flows: [Flow]) -> [(start: Date, total: Double)] {
        let calendar = Calendar.current
        let unit = trendUnit
        guard let current = calendar.dateInterval(of: unit, for: route.period.interval.start) else { return [] }
        let count = route.period.range == .all ? 6 : 12
        var buckets: [(Date, Date)] = []
        for step in stride(from: count - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: unit, value: -step, to: current.start),
                  let end = calendar.date(byAdding: unit, value: 1, to: start) else { continue }
            buckets.append((start, end))
        }
        return buckets.map { bucket in
            (bucket.0, flows.reduce(0) { $1.date >= bucket.0 && $1.date < bucket.1 ? $0 + $1.baseAmount : $0 })
        }
    }
}
