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

    @State private var addingAccount = false
    @State private var importing = false
    /// Accounts tapped on Home. Empty means "all": the summary, month and spending
    /// cards then cover every account; otherwise only the selected ones.
    @State private var selectedAccounts: Set<UUID> = []
    /// Opened from an account card's context menu (a tap selects it instead).
    @State private var openedAccount: Account?

    var body: some View {
        let ledger = LedgerSnapshot(accounts: accounts, records: records, baseCurrency: baseCurrency)
        let month = ReportPeriod.containing(.now, range: .month)
        // Drop selections of accounts that have since been archived or deleted.
        let scope = selectedAccounts.intersection(ledger.activeAccounts.map(\.uuid))
        let report = Report.build(
            flows: scope.isEmpty ? ledger.flows : ledger.flows.filter { $0.accountID.map(scope.contains) ?? false },
            period: month,
            // Picking an account excluded from stats is an explicit request to see it.
            excludedAccounts: ledger.excludedFromStats.subtracting(scope)
        )

        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if accounts.isEmpty {
                        WelcomeCard(onImport: { importing = true }, onAddAccount: { addingAccount = true })
                    } else {
                        accountsGrid(ledger)
                        summary(ledger: ledger, report: report, scope: scope)
                        MonthCard(report: report, currency: baseCurrency, accounts: scope)
                        if !report.expenseByGroup.isEmpty {
                            SpendingDonutCard(report: report, currency: baseCurrency, accounts: scope)
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
            .overlay(alignment: .bottomTrailing) {
                if !accounts.isEmpty {
                    FloatingAddButton { router.compose() }
                }
            }
            .sheet(isPresented: $addingAccount) { AccountEditView(account: nil) }
            .sheet(isPresented: $importing) { WalletImportView() }
            .navigationDestination(for: Record.self) { RecordDetailView(record: $0) }
            .navigationDestination(for: Account.self) { AccountDetailView(account: $0) }
            .navigationDestination(item: $openedAccount) { AccountDetailView(account: $0) }
            .sensoryFeedback(.selection, trigger: selectedAccounts)
            .task {
                // `-selectAccounts <n>`: pre-select the first n cards for screenshots; inert in Release.
                if let count = DebugFlags.value(after: "-selectAccounts").flatMap(Int.init) {
                    let active = accounts.filter { !$0.isArchived }.sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
                    selectedAccounts = Set(active.prefix(count).map(\.uuid))
                }
            }
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

    private func accountsGrid(_ ledger: LedgerSnapshot) -> some View {
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
            AccountPager(
                accounts: ledger.activeAccounts,
                balance: ledger.balance(of:),
                selection: $selectedAccounts,
                onOpen: { openedAccount = $0 },
                onAdd: { addingAccount = true }
            )
        }
    }

    // MARK: Summary

    private func summary(ledger: LedgerSnapshot, report: Report, scope: Set<UUID>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Summary", comment: "Home section title above the total balance")).font(.headline)
                Spacer()
                if !scope.isEmpty {
                    Button {
                        withAnimation(.snappy) { selectedAccounts = [] }
                    } label: {
                        Text(String(localized: "Clear", comment: "Home: button that deselects the account cards so the summary covers every account"))
                            .font(.subheadline.weight(.medium))
                    }
                    .transition(.opacity)
                }
            }
            NetWorthHero(ledger: ledger, report: report, scope: scope, currency: baseCurrency)
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

/// Accounts in pages of two by two (the last slot is "Add account"), one page per
/// swipe. The page being left shrinks and fades a touch so the motion has depth, and
/// dots below show how many pages there are and which one is showing.
private struct AccountPager: View {
    let accounts: [Account]
    let balance: (Account) -> Double
    /// Tapping a card adds it to or removes it from this set.
    @Binding var selection: Set<UUID>
    let onOpen: (Account) -> Void
    let onAdd: () -> Void

    @State private var page: Int? = 0

    private static let perPage = 4
    private static let spacing: CGFloat = 12
    /// The screen margin the first and last pages line up with.
    private static let margin: CGFloat = 16
    private static let gap: CGFloat = 12
    /// How far a centred page sits in from each screen edge; what's left after the
    /// gap is the sliver of the neighbouring page that shows.
    private static let peekInset: CGFloat = 36

    static func pageWidth(container: CGFloat, pages: Int) -> CGFloat {
        container - 2 * (pages > 1 ? peekInset : margin)
    }

    /// One page per swipe. The first page lines up with the screen margin, the last
    /// with the trailing margin, and the ones between sit centred with a neighbour
    /// peeking in on each side — the natural result of centring and clamping.
    private struct PeekPaging: ScrollTargetBehavior {
        let current: Int
        let pages: Int

        func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
            let container = context.containerSize.width
            let width = AccountPager.pageWidth(container: container, pages: pages)
            let step = width + AccountPager.gap
            let centring = (container - width) / 2
            let maxOffset = max(0, context.contentSize.width - container)

            // Where the gesture wanted to land, as the nearest page…
            let proposedCentre = context.originalTarget.rect.minX + container / 2
            var index = Int(((proposedCentre - AccountPager.margin - width / 2) / step).rounded())
            // …but never more than one page from where it started, and a flick
            // always moves at least one.
            let velocity = context.velocity.dx
            if index == current, abs(velocity) > 0.3 { index += velocity > 0 ? 1 : -1 }
            index = min(max(index, current - 1, 0), min(current + 1, pages - 1))

            let offset = AccountPager.margin + CGFloat(index) * step - centring
            target.rect.origin.x = min(max(offset, 0), maxOffset)
        }
    }

    private enum Slot: Identifiable {
        case account(Account)
        case add

        var id: AnyHashable {
            switch self {
            case .account(let account): AnyHashable(account.persistentModelID)
            case .add: AnyHashable("add")
            }
        }
    }

    var body: some View {
        let slots = accounts.map(Slot.account) + [.add]
        let pages = stride(from: 0, to: slots.count, by: Self.perPage).map {
            Array(slots[$0..<min($0 + Self.perPage, slots.count)])
        }
        // Every page keeps the same height, so the section never jumps while swiping.
        let rows = slots.count > 2 ? 2 : 1
        let height = CGFloat(rows) * AccountCard.compactHeight + CGFloat(rows - 1) * Self.spacing
        let current = min(page ?? 0, pages.count - 1)

        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(pages.indices, id: \.self) { index in
                        grid(pages[index])
                            .frame(height: height, alignment: .top)
                            .containerRelativeFrame(.horizontal) { width, _ in
                                Self.pageWidth(container: width, pages: pages.count)
                            }
                            .scrollTransition(axis: .horizontal) { content, phase in
                                // Neighbours recede toward the outside edge, so the
                                // sliver that peeks in stays put.
                                content
                                    .scaleEffect(1 - abs(phase.value) * 0.05,
                                                 anchor: phase.value > 0 ? .leading : .trailing)
                                    .opacity(1 - abs(phase.value) * 0.4)
                            }
                            .id(index)
                    }
                }
                .padding(.horizontal, Self.margin)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(PeekPaging(current: current, pages: pages.count))
            .scrollPosition(id: $page, anchor: .center)
            // Run edge to edge so neighbouring pages can peek in from the screen sides.
            .padding(.horizontal, -Self.margin)
            .sensoryFeedback(.selection, trigger: current)

            if pages.count > 1 {
                PageDots(count: pages.count, current: current) { index in
                    withAnimation(.smooth(duration: 0.4)) { page = index }
                }
            }
        }
    }

    private func grid(_ slots: [Slot]) -> some View {
        let column = GridItem(.flexible(), spacing: Self.spacing)
        return LazyVGrid(columns: [column, column], spacing: Self.spacing) {
            ForEach(slots) { slot in
                switch slot {
                case .account(let account):
                    let isSelected = selection.contains(account.uuid)
                    Button {
                        withAnimation(.snappy) {
                            if isSelected { selection.remove(account.uuid) } else { selection.insert(account.uuid) }
                        }
                    } label: {
                        AccountCard(account: account, balance: balance(account), width: nil, compact: true)
                            .overlay {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(.white, lineWidth: 3)
                                }
                            }
                            // Once something is picked, the cards left out step back.
                            .opacity(selection.isEmpty || isSelected ? 1 : 0.4)
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button {
                            onOpen(account)
                        } label: {
                            Label(String(localized: "Open account", comment: "Home: context menu item on an account card"), systemImage: "arrow.up.forward.square")
                        }
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityAction(named: Text(String(localized: "Open account", comment: "Home: context menu item on an account card"))) { onOpen(account) }
                case .add:
                    Button(action: onAdd) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.subheadline.weight(.semibold))
                            Text("Add account").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: AccountCard.compactHeight)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(.quaternary)
                        }
                        .contentShape(.rect(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

/// Page indicator: the current page stretches into a pill in the accent colour.
/// Tapping a dot jumps to that page; VoiceOver skips it, since every card is
/// reachable on its own.
private struct PageDots: View {
    let count: Int
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                    .frame(width: index == current ? 18 : 6, height: 6)
                    .padding(.vertical, 6)
                    .contentShape(.rect)
                    .onTapGesture { onSelect(index) }
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.25), value: current)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

private struct NetWorthHero: View {
    let ledger: LedgerSnapshot
    let report: Report
    /// The selected accounts; empty means every account.
    let scope: Set<UUID>
    let currency: String

    var body: some View {
        let series = sparkline()
        VStack(alignment: .leading, spacing: 16) {
            if series.count > 2 {
                // Scrub the line to read the balance on any of the last 30 days.
                TrendChart(series: series, currency: currency, plotHeight: 150, spacing: 16) { focused in
                    header(focused: focused)
                }
            } else {
                header(focused: nil)
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

    /// What the balance covers: everything, one account by name, or a count.
    private var scopeTitle: String {
        if scope.isEmpty { return String(localized: "Total balance") }
        if scope.count == 1, let account = ledger.account(scope.first) { return account.displayName }
        return String(localized: "\(scope.count) accounts", comment: "Home: the balance of several selected accounts")
    }

    private var balance: Double {
        scope.isEmpty
            ? ledger.netWorth
            : ledger.accounts.filter { scope.contains($0.uuid) }.reduce(0) { $0 + ledger.balanceInBase(of: $1) }
    }

    /// "Total balance" and today's figure, or the scrubbed day and its balance.
    private func header(focused: TrendPoint?) -> some View {
        let value = focused?.value ?? balance
        return VStack(alignment: .leading, spacing: 6) {
            Group {
                if let focused {
                    Text(focused.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                } else {
                    Text(scopeTitle)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))

            Text(Money.exact(value, code: currency))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                // Roll the digits for real changes, but follow a scrub instantly.
                .contentTransition(focused == nil ? .numericText(value: value) : .identity)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
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
        let accounts = scope.isEmpty ? ledger.refs : ledger.refs.filter { scope.contains($0.id) }
        return Ledger.netWorthSeries(accounts: accounts, flows: ledger.flows, rates: ledger.rates, buckets: buckets)
    }
}

// MARK: - Month

private struct MonthCard: View {
    let report: Report
    let currency: String
    /// The selected accounts, carried into the drill-down; empty means all.
    var accounts: Set<UUID> = []
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
        filter.accounts = accounts
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

/// This month's spending by group. No legend: tapping a slice shows its name,
/// amount and share in the centre; tapping it again goes back to the total.
struct SpendingDonutCard: View {
    let report: Report
    let currency: String
    /// The selected accounts, carried into the drill-down; empty means all.
    var accounts: Set<UUID> = []
    var title = String(localized: "Spending by category", comment: "Chart title")

    @Environment(AppRouter.self) private var router
    @State private var selected: String?

    private var slices: [Report.Slice] { Array(report.expenseByGroup.prefix(7)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: title, subtitle: report.period.title)
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
            .onDonutTap(total: slices.reduce(0) { $0 + $1.total }, innerRatio: 0.62) { angle in
                let hit = slice(at: angle)
                withAnimation(.snappy) { selected = selected == hit ? nil : hit }
            }
            .chartBackground { proxy in
                GeometryReader { geo in
                    if let frame = proxy.plotFrame {
                        let rect = geo[frame]
                        VStack(spacing: 0) {
                            if let selected, let slice = slices.first(where: { $0.key == selected }) {
                                let group = RecordGroup(rawValue: selected) ?? .other
                                Image(systemName: group.symbol)
                                    .font(.title3)
                                    .foregroundStyle(group.tint)
                                Text(group.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(Money.string(slice.total, code: currency))
                                    .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(1)
                                Text((slice.total / max(report.expense, 0.01)).formatted(.percent.precision(.fractionLength(0))))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(group.tint)
                            } else {
                                Text("Spent").font(.subheadline).foregroundStyle(.secondary)
                                Text(Money.string(report.expense, code: currency))
                                    .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                                    .minimumScaleFactor(0.5)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: rect.width * 0.56)
                        .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            // As wide as the card allows, up to 320pt, and always square.
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .sensoryFeedback(.selection, trigger: selected)
            // A different set of accounts may not have the focused slice at all.
            .onChange(of: accounts) { selected = nil }

            if let selected {
                Button {
                    var filter = TransactionFilter()
                    filter.categories = ["group:" + selected]
                    filter.accounts = accounts
                    filter.period = .custom
                    filter.customStart = report.period.interval.start
                    filter.customEnd = report.period.interval.end.addingTimeInterval(-1)
                    router.showTransactions(filter)
                } label: {
                    Label("Show these transactions", systemImage: "list.bullet")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
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
