import SwiftUI
import SwiftData
import Charts

/// The first screen: what you have, what this month looks like, and anything that
/// wants your attention — without digging into reports.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \Record.date, order: .reverse) private var records: [Record]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @AppStorage("hideBalances") private var hideBalances = false

    @State private var addingAccount = false
    @State private var importing = false

    var body: some View {
        let ledger = LedgerSnapshot(accounts: accounts, records: records, baseCurrency: baseCurrency)
        let month = ReportPeriod.containing(.now, range: .month)
        let report = Report.build(flows: ledger.flows, period: month, excludedAccounts: ledger.excludedFromStats)

        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if accounts.isEmpty {
                        WelcomeCard(onImport: { importing = true }, onAddAccount: { addingAccount = true })
                    } else {
                        NetWorthHero(ledger: ledger, report: report, currency: baseCurrency, hideBalances: $hideBalances)
                        accountsCarousel(ledger)
                        MonthCard(report: report, currency: baseCurrency)
                        if !report.expenseByGroup.isEmpty {
                            SpendingDonutCard(report: report, currency: baseCurrency)
                        }
                        if !budgets.isEmpty {
                            BudgetsCard(budgets: budgets, flows: ledger.flows, excluded: ledger.excludedFromStats, currency: baseCurrency)
                        }
                        lifecycleSuggestions(ledger: ledger)
                        recentCard(ledger: ledger)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .defaultScrollAnchor(DebugFlags.scrollAnchor)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        BudgetsView()
                    } label: {
                        Image(systemName: "target")
                    }
                    .accessibilityLabel(Text("Budgets"))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !accounts.isEmpty {
                    FloatingAddButton { router.compose() }
                }
            }
            .sheet(isPresented: $addingAccount) { AccountEditView(account: nil) }
            .sheet(isPresented: $importing) { WalletImportView() }
            .navigationDestination(for: Record.self) { RecordDetailView(record: $0) }
            .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return String(localized: "Good morning", comment: "Home title")
        case 12..<18: return String(localized: "Good afternoon", comment: "Home title")
        default: return String(localized: "Good evening", comment: "Home title")
        }
    }

    // MARK: Accounts

    private func accountsCarousel(_ ledger: LedgerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Accounts").font(.headline)
                Spacer()
                NavigationLink {
                    AccountsView()
                } label: {
                    Text("See all").font(.subheadline.weight(.medium))
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ledger.activeAccounts) { account in
                        NavigationLink(value: account) {
                            AccountCard(account: account, balance: ledger.balance(of: account))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    Button {
                        addingAccount = true
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.title3.weight(.semibold))
                            Text("Add account").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 110, height: 118)
                        .background {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .buttonStyle(PressableStyle())
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    // MARK: Lifecycle

    @ViewBuilder
    private func lifecycleSuggestions(ledger: LedgerSnapshot) -> some View {
        // "Meaningful" = at least five days of typical spending, so a coffee never asks.
        let threshold = max(1, ledgerAverageDaily(ledger) * 5)
        let candidates = LedgerActions.lifecycleCandidates(records: Array(records.prefix(600)), minimumBase: threshold)
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(
                    title: String(localized: "Bought something lasting?", comment: "Card title"),
                    subtitle: String(localized: "Track these purchases to see what they cost you per day.", comment: "Card subtitle")
                )
                ForEach(candidates) { record in
                    let flow = record.flow
                    HStack(spacing: 12) {
                        CategoryTile(symbol: flow.category.symbol, tint: flow.category.tint, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(flow.note.split(separator: "\n").first.map(String.init) ?? flow.category.label)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(Money.exact(flow.safeAmount, code: flow.currencyCode)) · \(flow.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button {
                            router.itemToConfirm = LedgerActions.trackAsItem(record, in: context)
                        } label: {
                            Text("Track")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                        Button {
                            withAnimation(.snappy) { record.lifecycleDismissed = true }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Dismiss"))
                    }
                }
            }
            .card()
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private func ledgerAverageDaily(_ ledger: LedgerSnapshot) -> Double {
        let period = ReportPeriod.containing(.now, range: .quarter)
        let report = Report.build(flows: ledger.flows, period: period, excludedAccounts: ledger.excludedFromStats)
        return report.averageDailyExpense
    }

    // MARK: Recent

    private func recentCard(ledger: LedgerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                Button("See all") { router.showTransactions(TransactionFilter()) }
                    .font(.subheadline.weight(.medium))
            }
            .padding(.bottom, 4)
            if records.isEmpty {
                Text("No transactions yet. Tap + to add your first.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(records.prefix(6)) { record in
                let flow = record.flow
                NavigationLink(value: record) {
                    RecordRow(flow: flow, accountLine: ledger.accountLine(for: flow), showsDate: true, linkedItemName: record.item?.displayName)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                if record.id != records.prefix(6).last?.id { Divider().padding(.leading, 52) }
            }
        }
        .card()
    }
}

// MARK: - Hero

private struct NetWorthHero: View {
    let ledger: LedgerSnapshot
    let report: Report
    let currency: String
    @Binding var hideBalances: Bool

    var body: some View {
        let series = sparkline()
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Total balance")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button {
                    withAnimation(.snappy) { hideBalances.toggle() }
                } label: {
                    Image(systemName: hideBalances ? "eye.slash.fill" : "eye.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(hideBalances ? Text("Show balances") : Text("Hide balances"))
                .sensoryFeedback(.selection, trigger: hideBalances)
            }
            .padding(.bottom, -10)

            Text(Money.exact(ledger.netWorth, code: currency))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(.numericText(value: ledger.netWorth))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .sensitive()

            if series.count > 2 {
                TrendChart(series: series, showsAxis: false)
                    .frame(height: 54)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .sensitive()
            }

            HStack(spacing: 10) {
                pill(symbol: "arrow.down.left", title: String(localized: "Income"), value: report.income, tint: .income)
                pill(symbol: "arrow.up.right", title: String(localized: "Spent"), value: report.expense, tint: Brand.amber)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroBackground(showsCurve: false))
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private func pill(symbol: String, title: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.18), in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(title) · \(Date.now.formatted(.dateTime.month(.abbreviated)))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(Money.string(value, code: currency))
                    .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .sensitive()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
    }

    /// Net worth at the end of each of the last 30 days.
    private func sparkline() -> [(date: Date, value: Double)] {
        let calendar = Calendar.current
        let today = Date.now.startOfDay
        let buckets = (0..<30).reversed().compactMap { offset -> DateInterval? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return DateInterval(start: day, end: next)
        }
        return Ledger.netWorthSeries(accounts: ledger.refs, flows: ledger.flows, rates: ledger.rates, buckets: buckets)
    }
}

// MARK: - Month

private struct MonthCard: View {
    let report: Report
    let currency: String
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                CardHeader(title: report.period.title, subtitle: String(localized: "Cash flow this month", comment: "Card subtitle"))
                if let change = report.expenseChange {
                    ChangeBadge(change: change)
                }
            }
            let maxValue = max(report.income, report.expense, 1)
            flowBar(title: String(localized: "Income"), value: report.income, fraction: report.income / maxValue, tint: .income) { show(.income) }
            flowBar(title: String(localized: "Expenses"), value: report.expense, fraction: report.expense / maxValue, tint: Brand.expense) { show(.expense) }
            Divider()
            HStack {
                FigureColumn(title: String(localized: "Net"), value: Money.string(report.net, code: currency), tint: report.net >= 0 ? .income : Brand.expense)
                Spacer()
                FigureColumn(title: String(localized: "Per day"), value: Money.string(report.averageDailyExpense, code: currency), alignment: .center)
                Spacer()
                FigureColumn(
                    title: String(localized: "Saved"),
                    value: report.savingsRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                    tint: (report.savingsRate ?? 0) >= 0 ? .primary : Brand.expense,
                    alignment: .trailing
                )
            }
        }
        .card()
    }

    /// This month's income or expenses in the Transactions tab.
    private func show(_ kind: RecordKind) {
        var filter = TransactionFilter()
        filter.kinds = [kind]
        filter.period = .thisMonth
        router.showTransactions(filter)
    }

    private func flowBar(title: String, value: Double, fraction: Double, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            flowBarContent(title: title, value: value, fraction: fraction, tint: tint)
                .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
    }

    private func flowBarContent(title: String, value: Double, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Text(Money.string(value, code: currency))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .sensitive()
                Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(tint.gradient).frame(width: max(8, geo.size.width * fraction))
                }
            }
            .frame(height: 10)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Donut

/// This month's spending by group. Tap a slice or legend row to focus it; tap the
/// centre to open the full report.
struct SpendingDonutCard: View {
    let report: Report
    let currency: String
    var title = String(localized: "Spending by category", comment: "Chart title")

    @Environment(AppRouter.self) private var router
    @State private var selectedAngle: Double?
    @State private var selected: String?
    @State private var lastHit: String?

    private var slices: [Report.Slice] { Array(report.expenseByGroup.prefix(7)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: title, subtitle: report.period.title)
            HStack(spacing: 16) {
                Chart(slices) { slice in
                    let group = RecordGroup(rawValue: slice.key) ?? .other
                    SectorMark(
                        angle: .value("Spent", slice.total),
                        innerRadius: .ratio(0.62),
                        outerRadius: .ratio(selected == slice.key ? 1 : 0.9),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(group.tint)
                    .opacity(selected == nil || selected == slice.key ? 1 : 0.35)
                }
                .chartAngleSelection(value: $selectedAngle)
                .chartBackground { proxy in
                    GeometryReader { geo in
                        if let frame = proxy.plotFrame {
                            let rect = geo[frame]
                            VStack(spacing: 0) {
                                if let selected, let slice = slices.first(where: { $0.key == selected }) {
                                    Image(systemName: (RecordGroup(rawValue: selected) ?? .other).symbol)
                                        .font(.caption)
                                        .foregroundStyle((RecordGroup(rawValue: selected) ?? .other).tint)
                                    Text((slice.total / max(report.expense, 1)).formatted(.percent.precision(.fractionLength(0))))
                                        .font(.system(.headline, design: .rounded).weight(.bold))
                                } else {
                                    Text("Spent").font(.caption2).foregroundStyle(.secondary)
                                    Text(Money.compact(report.expense, code: currency))
                                        .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                                        .minimumScaleFactor(0.6)
                                        .lineLimit(1)
                                        .sensitive()
                                }
                            }
                            .frame(width: rect.width * 0.55)
                            .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }
                .frame(width: 140, height: 140)
                .onChange(of: selectedAngle) { _, angle in
                    guard let angle else { lastHit = nil; return }
                    let hit = slice(at: angle)
                    guard hit != lastHit else { return }
                    let isNewGesture = lastHit == nil
                    lastHit = hit
                    withAnimation(.snappy) { selected = isNewGesture && selected == hit ? nil : hit }
                }
                .sensoryFeedback(.selection, trigger: selected)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(slices.prefix(5)) { slice in
                        let group = RecordGroup(rawValue: slice.key) ?? .other
                        Button {
                            withAnimation(.snappy) { selected = selected == slice.key ? nil : slice.key }
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(group.tint).frame(width: 8, height: 8)
                                Text(group.label)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .foregroundStyle(selected == nil || selected == slice.key ? .primary : .secondary)
                                Spacer(minLength: 4)
                                Text(Money.compact(slice.total, code: currency))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .sensitive()
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let selected {
                Button {
                    var filter = TransactionFilter()
                    filter.categories = ["group:" + selected]
                    filter.period = .custom
                    filter.customStart = report.period.interval.start
                    filter.customEnd = report.period.interval.end.addingTimeInterval(-1)
                    router.showTransactions(filter)
                } label: {
                    Label("Show these transactions", systemImage: "list.bullet")
                        .font(.subheadline.weight(.semibold))
                }
                .transition(.opacity)
            }
        }
        .card()
    }

    private func slice(at angle: Double) -> String? {
        var running = 0.0
        for slice in slices {
            running += slice.total
            if angle <= running { return slice.key }
        }
        return slices.last?.key
    }
}

// MARK: - Welcome

private struct WelcomeCard: View {
    let onImport: () -> Void
    let onAddAccount: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            BrandMark(size: 84)
                .shadow(color: Brand.leather.opacity(0.35), radius: 20, y: 8)
                .padding(.top, 12)
            VStack(spacing: 6) {
                Text("Let's set up your wallet")
                    .font(.title2.bold())
                Text("Bring your history over from BudgetBakers Wallet, or start fresh with your first account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                Button(action: onImport) {
                    Label("Import from BudgetBakers", systemImage: "square.and.arrow.down.on.square")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                Button(action: onAddAccount) {
                    Label("Add an account", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 16))
            }
        }
        .padding(20)
        .card()
        .padding(.top, 20)
    }
}
