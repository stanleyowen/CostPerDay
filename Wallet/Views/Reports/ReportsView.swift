import SwiftUI
import SwiftData
import Charts

/// Detailed reports for any week, month, quarter, year or all time. Every chart is
/// also a filter: tap a slice, bar, day, weekday, label, income source or account and
/// the whole report narrows to it; tap a bar in a long range to zoom into it.
struct ReportsView: View {
    @Query(sort: \Record.date, order: .reverse) private var records: [Record]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault

    /// The ledger snapshot is the expensive part (reading every record out of
    /// SwiftData), and it doesn't depend on the filter or period. Building it here,
    /// above the view that owns that state, means a tap on a chart only reruns the
    /// cheap report maths — the snapshot is rebuilt only when the data changes.
    var body: some View {
        ReportsContent(
            records: records,
            accounts: accounts,
            ledger: LedgerSnapshot(accounts: accounts, records: records, baseCurrency: baseCurrency)
        )
    }
}

private struct ReportsContent: View {
    let records: [Record]
    let accounts: [Account]
    let ledger: LedgerSnapshot
    @Environment(AppRouter.self) private var router
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @AppStorage("reportRange") private var rangeRaw = ReportRange.month.rawValue

    @State private var anchor = Date.now
    @State private var accountFilter: UUID?
    @State private var focus = ReportFocus()
    /// Where each zoom came from, so the filter bar can step back out.
    @State private var zoomTrail: [ZoomStep] = []
    @State private var breakdownByGroup = true
    @State private var exportURL: URL?
    @State private var filterTrigger = 0

    struct ZoomStep: Hashable {
        let range: ReportRange
        let anchor: Date
        let title: String
    }

    private var range: ReportRange { ReportRange(rawValue: rangeRaw) ?? .month }

    var body: some View {
        let earliest = ledger.flows.last?.date
        let period = ReportPeriod.containing(anchor, range: range, earliest: earliest)
        let report = Report.build(flows: ledger.flows, period: period, excludedAccounts: ledger.excludedFromStats, accountFilter: accountFilter, focus: focus)
        // The weekday chart keeps every weekday visible while one is selected.
        let weekdayReport = focus.weekday == nil ? report
            : Report.build(flows: ledger.flows, period: period, excludedAccounts: ledger.excludedFromStats, accountFilter: accountFilter, focus: focus.withoutWeekday)
        let isFiltered = !focus.isEmpty || accountFilter != nil || !zoomTrail.isEmpty

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    rangePicker
                    periodNavigator(period: period, earliest: earliest)

                    if isFiltered {
                        filterBar(period: period, report: report, ledger: ledger)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if records.isEmpty {
                        ContentUnavailableView("No data yet", systemImage: "chart.pie", description: Text("Reports appear once you've recorded some transactions."))
                            .padding(.top, 40)
                    } else {
                        SummaryCard(report: report, currency: baseCurrency)
                        if let day = focus.day {
                            DayCard(day: day, flows: dayFlows(day, ledger: ledger), records: records, ledger: ledger, currency: baseCurrency) {
                                setFocus { $0.day = nil }
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                        }
                        if report.transactionCount > 0 {
                            CashFlowChartCard(report: report, currency: baseCurrency, highlightedDay: focus.day, onSelect: select(bucket:))
                            if report.expenseCount > 0 {
                                BreakdownCard(
                                    report: report, currency: baseCurrency, byGroup: $breakdownByGroup,
                                    focusedCategory: focus.category, accountFilter: accountFilter,
                                    onSelect: { key in setFocus { $0.category = $0.category == key ? nil : key } }
                                )
                            }
                            if !report.incomeByCategory.isEmpty {
                                IncomeCard(report: report, currency: baseCurrency, focusedCategory: focus.category) { key in
                                    setFocus { $0.category = $0.category == key ? nil : key }
                                }
                            }
                            if range == .month {
                                CalendarHeatmapCard(report: report, currency: baseCurrency, selectedDay: focus.day) { day in
                                    setFocus { $0.day = $0.day == day ? nil : day }
                                }
                            }
                            if range != .week {
                                WeekdayCard(report: weekdayReport, currency: baseCurrency, selected: focus.weekday) { weekday in
                                    setFocus { $0.weekday = $0.weekday == weekday ? nil : weekday }
                                }
                            }
                            NetWorthTrendCard(ledger: ledger, period: period, currency: baseCurrency)
                            TopExpensesCard(report: report, ledger: ledger, records: records, currency: baseCurrency)
                            if !report.byLabel.isEmpty {
                                LabelsCard(report: report, currency: baseCurrency, selected: focus.label) { label in
                                    setFocus { $0.label = $0.label == label ? nil : label }
                                }
                            }
                            if accountFilter == nil, report.expenseByAccount.count > 1 {
                                AccountsBreakdownCard(report: report, ledger: ledger, currency: baseCurrency) { id in
                                    withAnimation(.snappy) { accountFilter = id }
                                    filterTrigger += 1
                                }
                            }
                            InsightsCard(report: report, currency: baseCurrency)
                        } else {
                            ContentUnavailableView(
                                isFiltered ? "Nothing matches" : "Nothing in this period",
                                systemImage: isFiltered ? "line.3.horizontal.decrease.circle" : "calendar.badge.exclamationmark",
                                description: Text(isFiltered ? "Clear a filter above, or try another period." : "Try an earlier period or a longer range.")
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(.snappy, value: period)
                .animation(.snappy, value: focus)
                .animation(.snappy, value: accountFilter)
            }
            .defaultScrollAnchor(DebugFlags.scrollAnchor)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Account", selection: $accountFilter.animation(.snappy)) {
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
                        let matching = records.filter { record in
                            guard period.contains(record.date) else { return false }
                            let flow = record.flow
                            if let accountFilter, flow.accountID != accountFilter && flow.toAccountID != accountFilter { return false }
                            return focus.matches(flow)
                        }
                        exportURL = try? TransactionExport.writeCSV(records: matching, accounts: accounts, baseCurrency: baseCurrency, title: period.title)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(Text("Export CSV"))
                    .disabled(report.transactionCount == 0)
                }
            }
            .sensoryFeedback(.selection, trigger: filterTrigger)
            .sheet(item: $exportURL) { ShareSheet(url: $0) }
            .navigationDestination(for: Record.self) { RecordDetailView(record: $0) }
            .navigationDestination(for: CategoryReportRoute.self) { route in
                CategoryReportView(route: route, records: records, accounts: accounts)
            }
            .onChange(of: period) { _, newPeriod in
                if let day = focus.day, !newPeriod.contains(day) { focus.day = nil }
            }
            .onAppear {
                // `-reportFocus <category key>` / `-reportDay <d>`: screenshot hooks, inert in Release.
                if let key = DebugFlags.value(after: "-reportFocus") { focus.category = key }
                if let text = DebugFlags.value(after: "-reportDay"), let d = Int(text),
                   let date = Calendar.current.date(byAdding: .day, value: d - 1, to: period.interval.start) {
                    focus.day = date
                }
            }
        }
    }

    // MARK: Filtering

    private func setFocus(_ change: (inout ReportFocus) -> Void) {
        withAnimation(.snappy) { change(&focus) }
        filterTrigger += 1
    }

    /// A bar in a day-by-day chart picks that day; a bar standing for a longer
    /// stretch zooms the report into it.
    private func select(bucket: Report.Bucket) {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: bucket.start, to: bucket.end).day ?? 1
        if days <= 1 {
            setFocus { $0.day = $0.day == bucket.start ? nil : bucket.start }
            return
        }
        let target: ReportRange = days <= 7 ? .week : days <= 31 ? .month : .year
        let current = ReportPeriod.containing(anchor, range: range)
        withAnimation(.snappy) {
            zoomTrail.append(ZoomStep(range: range, anchor: anchor, title: current.title))
            rangeRaw = target.rawValue
            anchor = bucket.start
            focus.day = nil
        }
        filterTrigger += 1
    }

    private func zoomOut() {
        guard let step = zoomTrail.popLast() else { return }
        withAnimation(.snappy) {
            rangeRaw = step.range.rawValue
            anchor = step.anchor
            focus.day = nil
        }
        filterTrigger += 1
    }

    private func clearAll() {
        withAnimation(.snappy) {
            focus = ReportFocus()
            accountFilter = nil
            if let first = zoomTrail.first {
                rangeRaw = first.range.rawValue
                anchor = first.anchor
            }
            zoomTrail = []
        }
        filterTrigger += 1
    }

    private func dayFlows(_ day: Date, ledger: LedgerSnapshot) -> [Flow] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        return ledger.flows.filter { flow in
            guard flow.date >= day, flow.date < end else { return false }
            if let accountFilter, flow.accountID != accountFilter && flow.toAccountID != accountFilter { return false }
            return focus.matches(flow)
        }
        .sorted { $0.date > $1.date }
    }

    /// The same narrowing, expressed as a Transactions filter.
    private func transactionFilter(period: ReportPeriod) -> TransactionFilter {
        var filter = TransactionFilter()
        filter.period = .custom
        let interval = focus.day.map { DateInterval(start: $0, duration: 86_400) } ?? period.interval
        filter.customStart = interval.start
        filter.customEnd = interval.end.addingTimeInterval(-1)
        if let category = focus.category { filter.categories = [category] }
        if let label = focus.label { filter.labels = [label] }
        if let accountFilter { filter.accounts = [accountFilter] }
        filter.weekday = focus.weekday
        filter.kinds = focus.category == nil ? [.expense, .income] : []
        return filter
    }

    private func filterBar(period: ReportPeriod, report: Report, ledger: LedgerSnapshot) -> some View {
        let weekdaySymbols = Calendar.current.standaloneWeekdaySymbols
        let count = focus.day.map { dayFlows($0, ledger: ledger).filter { $0.kind != .transfer }.count } ?? report.transactionCount
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let step = zoomTrail.last {
                        Chip(title: step.title, systemImage: "chevron.left", isSelected: false, action: zoomOut)
                    }
                    if let category = focus.category {
                        let display = CategoryReportRoute(key: category, period: period, accountFilter: nil).display
                        if let parent = focus.parentCategory {
                            let parentDisplay = CategoryReportRoute(key: parent, period: period, accountFilter: nil).display
                            Chip(title: parentDisplay.label, systemImage: "chevron.left", isSelected: false) {
                                setFocus { $0.category = parent }
                            }
                        }
                        Chip(title: display.label, systemImage: "xmark", isSelected: true, tint: display.tint) {
                            setFocus { $0.category = nil }
                        }
                    }
                    if let label = focus.label {
                        Chip(title: label, systemImage: "xmark", isSelected: true, tint: LabelTint.color(for: label)) {
                            setFocus { $0.label = nil }
                        }
                    }
                    if let weekday = focus.weekday, weekdaySymbols.indices.contains(weekday - 1) {
                        Chip(title: weekdaySymbols[weekday - 1], systemImage: "xmark", isSelected: true, tint: .purple) {
                            setFocus { $0.weekday = nil }
                        }
                    }
                    if let day = focus.day {
                        Chip(title: day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), systemImage: "xmark", isSelected: true, tint: Brand.accent) {
                            setFocus { $0.day = nil }
                        }
                    }
                    if let account = ledger.account(accountFilter) {
                        Chip(title: account.displayName, systemImage: "xmark", isSelected: true, tint: account.tint.color) {
                            withAnimation(.snappy) { accountFilter = nil }
                            filterTrigger += 1
                        }
                    }
                    Button("Clear all", action: clearAll)
                        .font(.subheadline.weight(.semibold))
                        .padding(.leading, 4)
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)

            if count > 0 {
                Button {
                    router.showTransactions(transactionFilter(period: period))
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Show \(count) transactions")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Brand.accent.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
    }

    // MARK: Period

    private var rangePicker: some View {
        Picker("Range", selection: Binding(get: { range }, set: { newRange in
            withAnimation(.snappy) {
                rangeRaw = newRange.rawValue
                anchor = .now
                zoomTrail = []
                focus.day = nil
            }
        })) {
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

// MARK: - Tap handling

extension View {
    /// Turns a tap on a chart's plot area into the x value under the finger. A tap,
    /// not a drag, so the surrounding scroll view keeps scrolling normally.
    func onChartTap<X: Plottable>(_ type: X.Type, perform action: @escaping (X) -> Void) -> some View {
        chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .onTapGesture { location in
                        guard let frame = proxy.plotFrame else { return }
                        let x = location.x - geo[frame].origin.x
                        if let value: X = proxy.value(atX: x) { action(value) }
                    }
            }
        }
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
                FigureColumn(title: String(localized: "Net"), value: Money.string(report.net, code: currency), tint: report.net >= 0 ? .income : Brand.expense, alignment: .center)
                Spacer()
                FigureColumn(title: String(localized: "Saved"), value: report.savingsRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—", alignment: .trailing)
            }
        }
        .card()
    }
}

/// The transactions behind a tapped day.
private struct DayCard: View {
    let day: Date
    let flows: [Flow]
    let records: [Record]
    let ledger: LedgerSnapshot
    let currency: String
    let onClose: () -> Void

    var body: some View {
        let ids = Set(flows.prefix(30).map(\.id))
        let byID = Dictionary(records.lazy.filter { ids.contains($0.uuid) }.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        let spent = flows.filter { $0.kind == .expense }.reduce(0) { $0 + $1.baseAmount }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                CardHeader(
                    title: day.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                    subtitle: String(localized: "\(flows.count) transactions", comment: "Chart subtitle")
                )
                Text(Money.string(spent, code: currency))
                    .font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss"))
            }
            .padding(.bottom, 2)
            ForEach(flows.prefix(30)) { flow in
                if let record = byID[flow.id] {
                    NavigationLink(value: record) {
                        RecordRow(flow: flow, accountLine: ledger.accountLine(for: flow), linkedItemName: record.item?.displayName)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }
}

// MARK: - Cash flow

private struct CashFlowChartCard: View {
    let report: Report
    let currency: String
    let highlightedDay: Date?
    let onSelect: (Report.Bucket) -> Void
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
        let focused = highlightedDay.flatMap { day in report.buckets.first { day >= $0.start && day < $0.end } }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                CardHeader(
                    title: showsIncome ? String(localized: "Cash flow", comment: "Chart title") : String(localized: "Spending", comment: "Chart title"),
                    subtitle: unit == .day
                        ? String(localized: "Tap a day to see its transactions", comment: "Chart hint")
                        : String(localized: "Tap a bar to zoom in", comment: "Chart hint")
                )
                if let focused {
                    VStack(alignment: .trailing, spacing: 1) {
                        if showsIncome {
                            Text(verbatim: "+\(Money.string(focused.income, code: currency))").foregroundStyle(Color.income)
                        }
                        Text(verbatim: "−\(Money.string(focused.expense, code: currency))").foregroundStyle(Brand.expense)
                        Text(label(for: focused.start)).foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.semibold).monospacedDigit())
                }
            }
            Chart {
                ForEach(report.buckets) { bucket in
                    let dimmed = focused != nil && focused?.start != bucket.start
                    if showsIncome {
                        BarMark(x: .value("Period", bucket.start, unit: unit), y: .value("Amount", bucket.income))
                            .foregroundStyle(Color.income.gradient)
                            .cornerRadius(3)
                            .opacity(dimmed ? 0.3 : 1)
                    }
                    BarMark(x: .value("Period", bucket.start, unit: unit), y: .value("Amount", showsIncome ? -bucket.expense : bucket.expense))
                        .foregroundStyle(Brand.expense.gradient)
                        .cornerRadius(3)
                        .opacity(dimmed ? 0.3 : 1)
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
            .onChartTap(Date.self) { date in
                if let bucket = report.buckets.first(where: { date >= $0.start && date < $0.end }) {
                    onSelect(bucket)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Money.compact(abs(v), code: currency)).font(.caption2) }
                    }
                }
            }
            .frame(height: 200)
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

/// Where the money went. Tapping a slice or row filters the whole report to it;
/// once a group is in focus the card drills into that group's categories.
private struct BreakdownCard: View {
    let report: Report
    let currency: String
    @Binding var byGroup: Bool
    let focusedCategory: String?
    let accountFilter: UUID?
    let onSelect: (String) -> Void

    /// Raw touch angles go here, not into view state: only a change of slice updates the card.
    @State private var angleSink = SelectionSink<Double>()
    @State private var lastHit: String?

    /// Groups only when nothing is focused and the user asked for groups; inside a
    /// focused group the slices are its categories.
    private var showsGroups: Bool { focusedCategory == nil && byGroup }

    /// Each slice's full filter key.
    private func key(for slice: Report.Slice) -> String {
        showsGroups ? "group:" + slice.key : slice.key
    }

    var body: some View {
        let slices = showsGroups ? report.expenseByGroup : report.expenseByCategory
        let maxTotal = max(slices.first?.total ?? 1, 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardHeader(
                    title: String(localized: "Where it went", comment: "Chart title"),
                    subtitle: String(localized: "Tap to filter the report", comment: "Chart hint")
                )
                if focusedCategory == nil {
                    Picker("Breakdown", selection: $byGroup) {
                        Text("Groups").tag(true)
                        Text("Categories").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 190)
                }
            }

            Chart(slices.prefix(8)) { slice in
                SectorMark(
                    angle: .value("Spent", slice.total),
                    innerRadius: .ratio(0.6),
                    outerRadius: .ratio(focusedCategory == key(for: slice) ? 1 : 0.92),
                    angularInset: 1.2
                )
                .cornerRadius(3)
                .foregroundStyle(display(slice.key).tint)
            }
            .chartAngleSelection(value: angleSink.binding { angle in
                // One selection per tap: the first slice touched in each gesture.
                guard let angle else { lastHit = nil; return }
                guard lastHit == nil, let hit = slice(at: angle, in: Array(slices.prefix(8))) else { return }
                lastHit = hit.key
                onSelect(key(for: hit))
            })
            .frame(height: 170)
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let frame = proxy.plotFrame {
                        let rect = geo[frame]
                        VStack(spacing: 0) {
                            Text("\(report.expenseCount) expenses").font(.caption2).foregroundStyle(.secondary)
                            Text(Money.compact(report.expense, code: currency))
                                .font(.system(.headline, design: .rounded).weight(.bold))
                        }
                        .position(x: rect.midX, y: rect.midY)
                    }
                }
            }

            VStack(spacing: 2) {
                ForEach(slices) { slice in
                    let display = display(slice.key)
                    let selected = focusedCategory == key(for: slice)
                    HStack(spacing: 10) {
                        Button {
                            onSelect(key(for: slice))
                        } label: {
                            HStack(spacing: 10) {
                                CategoryTile(symbol: display.symbol, tint: display.tint, size: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(display.label).font(.subheadline.weight(selected ? .bold : .medium)).lineLimit(1)
                                        Spacer(minLength: 6)
                                        Text(Money.string(slice.total, code: currency))
                                            .font(.subheadline.weight(.semibold).monospacedDigit())
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
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])

                        NavigationLink(value: CategoryReportRoute(key: key(for: slice), period: report.period, accountFilter: accountFilter)) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, height: 36)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Details"))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(selected ? display.tint.opacity(0.1) : .clear, in: .rect(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .card()
        .animation(.snappy, value: byGroup)
    }

    private func display(_ key: String) -> RecordCategoryDisplay {
        if showsGroups, let group = RecordGroup(rawValue: key) {
            return RecordCategoryDisplay(key: key, label: group.label, symbol: group.symbol, tint: group.tint, group: group, isMissing: false)
        }
        return RecordCategoryDisplay.resolve(key)
    }

    private func slice(at angle: Double, in slices: [Report.Slice]) -> Report.Slice? {
        var running = 0.0
        for slice in slices {
            running += slice.total
            if angle <= running { return slice }
        }
        return slices.last
    }
}

private struct IncomeCard: View {
    let report: Report
    let currency: String
    let focusedCategory: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: String(localized: "Income sources", comment: "Chart title"), subtitle: String(localized: "\(report.incomeCount) transactions", comment: "Chart subtitle"))
            ForEach(report.incomeByCategory.prefix(6)) { slice in
                let display = RecordCategoryDisplay.resolve(slice.key)
                let selected = focusedCategory == slice.key
                Button {
                    onSelect(slice.key)
                } label: {
                    HStack(spacing: 10) {
                        CategoryTile(symbol: display.symbol, tint: display.tint, size: 30)
                        Text(display.label).font(.subheadline.weight(selected ? .bold : .regular)).lineLimit(1)
                        Spacer()
                        Text(Money.string(slice.total, code: currency))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.income)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(selected ? Color.income.opacity(0.1) : .clear, in: .rect(cornerRadius: 12, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .card()
    }
}

// MARK: - Calendar & weekday

private struct CalendarHeatmapCard: View {
    let report: Report
    let currency: String
    let selectedDay: Date?
    let onSelect: (Date) -> Void

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
                CardHeader(title: String(localized: "Spending calendar", comment: "Chart title"), subtitle: String(localized: "Tap a day to see its transactions", comment: "Chart hint"))
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
                        onSelect(day)
                    } label: {
                        Text("\(offset + 1)")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(intensity > 0.55 ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(
                                value > 0 ? AnyShapeStyle(Brand.expense.opacity(0.15 + 0.85 * intensity)) : AnyShapeStyle(Color.primary.opacity(isFuture ? 0.02 : 0.05)),
                                in: .rect(cornerRadius: 8, style: .continuous)
                            )
                            .overlay {
                                if selectedDay == day {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary, lineWidth: 2)
                                }
                            }
                            .scaleEffect(selectedDay == day ? 1.08 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFuture)
                    .accessibilityLabel(Text(day.formatted(date: .abbreviated, time: .omitted)))
                    .accessibilityValue(Text(Money.string(value, code: currency)))
                    .accessibilityAddTraits(selectedDay == day ? .isSelected : [])
                }
            }
        }
        .card()
    }
}

private struct WeekdayCard: View {
    let report: Report
    let currency: String
    let selected: Int?
    /// Receives a `Calendar` weekday (1 = Sunday).
    let onSelect: (Int) -> Void

    var body: some View {
        let calendar = Calendar.current
        let order = (0..<7).map { ($0 + calendar.firstWeekday - 1) % 7 }
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let peak = report.weekdayExpense.max() ?? 0
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: String(localized: "By day of week", comment: "Chart title"), subtitle: String(localized: "Tap to filter the report", comment: "Chart hint"))
            Chart(order, id: \.self) { index in
                let isSelected = selected == index + 1
                BarMark(x: .value("Day", symbols[index]), y: .value("Average", report.weekdayExpense[index]))
                    .foregroundStyle(
                        isSelected || (selected == nil && report.weekdayExpense[index] == peak && peak > 0)
                            ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary.opacity(selected == nil ? 0.35 : 0.2))
                    )
                    .cornerRadius(5)
            }
            .onChartTap(String.self) { symbol in
                if let index = symbols.firstIndex(of: symbol) { onSelect(index + 1) }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel { if let v = value.as(Double.self) { Text(Money.compact(v, code: currency)).font(.caption2) } }
                }
            }
            .frame(height: 150)
        }
        .card()
    }
}

// MARK: - Net worth

private struct NetWorthTrendCard: View {
    let ledger: LedgerSnapshot
    let period: ReportPeriod
    let currency: String

    var body: some View {
        let buckets = period.buckets().filter { $0.start <= Date.now }
        let series = Ledger.netWorthSeries(accounts: ledger.refs, flows: ledger.flows, rates: ledger.rates, buckets: buckets)
        if series.count > 1 {
            TrendChart(series: series, currency: currency, plotHeight: 190) { focused in
                HStack(alignment: .top) {
                    CardHeader(title: String(localized: "Balance trend", comment: "Chart title"), subtitle: String(localized: "All accounts, at the end of each period", comment: "Chart subtitle"))
                    if let focused {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Money.string(focused.value, code: currency)).font(.subheadline.weight(.bold).monospacedDigit())
                            Text(focused.date.formatted(.dateTime.day().month(.abbreviated).year())).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
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
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        let maxTotal = max(report.byLabel.first?.total ?? 1, 1)
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: String(localized: "By label", comment: "Chart title"), subtitle: String(localized: "Tap to filter the report", comment: "Chart hint"))
            ForEach(report.byLabel.prefix(8)) { slice in
                let isSelected = selected == slice.key
                Button {
                    onSelect(slice.key)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(slice.key).font(.subheadline.weight(isSelected ? .bold : .medium)).foregroundStyle(.primary)
                            Text(verbatim: "\(slice.count)×").font(.caption).foregroundStyle(.tertiary)
                            Spacer()
                            Text(Money.string(slice.total, code: currency)).font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        GeometryReader { geo in
                            Capsule().fill(LabelTint.color(for: slice.key).gradient).frame(width: max(5, geo.size.width * slice.total / maxTotal))
                        }
                        .frame(height: 5)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(isSelected ? LabelTint.color(for: slice.key).opacity(0.1) : .clear, in: .rect(cornerRadius: 12, style: .continuous))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .card()
    }
}

private struct AccountsBreakdownCard: View {
    let report: Report
    let ledger: LedgerSnapshot
    let currency: String
    let onSelect: (UUID) -> Void

    var body: some View {
        let slices = Array(report.expenseByAccount.prefix(6))
        let maxTotal = max(slices.first?.total ?? 1, 1)
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: String(localized: "Spending by account", comment: "Chart title"), subtitle: String(localized: "Tap to filter the report", comment: "Chart hint"))
            ForEach(slices) { slice in
                if let id = UUID(uuidString: slice.key), let account = ledger.account(id) {
                    Button {
                        onSelect(id)
                    } label: {
                        HStack(spacing: 10) {
                            CategoryTile(symbol: account.kind.symbol, tint: account.tint.color, size: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(account.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Spacer()
                                    Text(Money.string(slice.total, code: currency)).font(.subheadline.weight(.semibold).monospacedDigit())
                                }
                                GeometryReader { geo in
                                    Capsule().fill(account.tint.color.gradient).frame(width: max(5, geo.size.width * slice.total / maxTotal))
                                }
                                .frame(height: 5)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
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
    /// A bar tapped in the trend chart: its period replaces the report's below.
    @State private var selectedBucket: DateInterval?

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
        let shown = selectedBucket ?? route.period.interval
        let inPeriod = matching.filter { $0.date >= shown.start && $0.date < shown.end }
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
                            Text(selectedBucket.map { title(for: $0.start) } ?? route.period.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(selectedBucket == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(display.tint))
                                .contentTransition(.opacity)
                            Text(Money.string(total, code: baseCurrency))
                                .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                        }
                        Spacer()
                        Text(verbatim: "\(inPeriod.count)×").font(.headline).foregroundStyle(.secondary)
                    }
                    if trend.count > 1 {
                        Chart(trend, id: \.start) { bucket in
                            BarMark(x: .value("Period", bucket.start, unit: trendUnit), y: .value("Spent", bucket.total))
                                .foregroundStyle(bucket.start >= shown.start && bucket.start < shown.end ? AnyShapeStyle(display.tint.gradient) : AnyShapeStyle(display.tint.opacity(0.3)))
                                .cornerRadius(4)
                        }
                        .onChartTap(Date.self) { date in
                            guard let bucket = trend.first(where: { date >= $0.start && date < $0.end }) else { return }
                            let interval = DateInterval(start: bucket.start, end: bucket.end)
                            withAnimation(.snappy) {
                                selectedBucket = interval == route.period.interval || selectedBucket == interval ? nil : interval
                            }
                        }
                        .sensoryFeedback(.selection, trigger: selectedBucket)
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                                AxisGridLine().foregroundStyle(.quaternary)
                                AxisValueLabel { if let v = value.as(Double.self) { Text(Money.compact(v, code: baseCurrency)).font(.caption2) } }
                            }
                        }
                        .frame(height: 140)
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
                            Text(Money.string(entry.total, code: baseCurrency)).monospacedDigit().foregroundStyle(.secondary)
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

    private func title(for start: Date) -> String {
        switch trendUnit {
        case .weekOfYear: start.formatted(.dateTime.day().month(.abbreviated).year())
        case .month: start.formatted(.dateTime.month(.wide).year())
        default: start.formatted(.dateTime.year())
        }
    }

    /// The selected period and the eleven before it, so the bar for "now" has context.
    private func trendSeries(flows: [Flow]) -> [(start: Date, end: Date, total: Double)] {
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
            (bucket.0, bucket.1, flows.reduce(0) { $1.date >= bucket.0 && $1.date < bucket.1 ? $0 + $1.baseAmount : $0 })
        }
    }
}
