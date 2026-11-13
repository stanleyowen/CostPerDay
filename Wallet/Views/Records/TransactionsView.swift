import SwiftUI
import SwiftData

/// The full ledger: searchable, filterable, grouped by day with each day's total.
struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \Record.date, order: .reverse) private var records: [Record]
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault

    @State private var search = ""
    @State private var visibleLimit = 400
    @State private var showingFilters = false

    var body: some View {
        @Bindable var router = router
        let ledger = LedgerSnapshot(accounts: accounts, records: [], baseCurrency: baseCurrency)
        let snapshot = Snapshot(records: records, filter: router.transactionFilter, search: search, limit: visibleLimit)

        NavigationStack {
            List {
                if !records.isEmpty {
                    Section {
                        // Scrolls with the list, like Reports' period control.
                        TransactionPeriodControl(period: $router.transactionFilter.period)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        summary(snapshot)
                            // Flush with the day sections below.
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        // The period has its own control above; these are the rest.
                        if !router.transactionFilter.accounts.isEmpty || router.transactionFilter.detailCount > 0 {
                            activeFilters
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                }

                ForEach(snapshot.days) { day in
                    Section {
                        ForEach(day.records) { record in
                            row(record, ledger: ledger)
                        }
                    } header: {
                        DayHeader(day: day.date, net: day.net, currency: baseCurrency)
                    }
                }

                if snapshot.hasMore {
                    Button {
                        visibleLimit += 400
                    } label: {
                        Text("Show more")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .overlay {
                if records.isEmpty {
                    ContentUnavailableView {
                        Label("No transactions yet", systemImage: "list.bullet.rectangle.portrait")
                    } description: {
                        Text("Tap + to record an expense, or import your history from BudgetBakers in Settings.")
                    }
                } else if snapshot.days.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: Text("Notes, labels, amounts"))
            .navigationTitle("Transactions")
            // The period is at the top of the list; the other filters are behind
            // the toolbar button. The bottom is left to the tab bar and +.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    FilterToolbarButton(count: TransactionFilterSheet.count(router.transactionFilter, part: .all)) { showingFilters = true }
                }
            }
            .sheet(isPresented: $showingFilters) {
                TransactionFilterSheet(filter: $router.transactionFilter, part: .all,
                                       accounts: accounts.filter { !$0.isArchived }, labels: snapshot.allLabels)
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                FloatingAddButton { router.compose() }
            }
            .onChange(of: router.transactionFilter) { _, _ in visibleLimit = 400 }
        }
    }

    private func row(_ record: Record, ledger: LedgerSnapshot) -> some View {
        let flow = record.flow
        return RecordLink(record: record) {
            RecordRow(flow: flow, accountLine: ledger.accountLine(for: flow), linkedItemName: record.item?.displayName)
        }
        .recordActions(record)
    }

    /// Income, expenses and net, one per row so each figure has room to read.
    private func summary(_ snapshot: Snapshot) -> some View {
        let net = snapshot.income - snapshot.expense
        return VStack(spacing: 0) {
            kindToggle(.income) {
                summaryRow(symbol: "arrow.down.left", tint: .income, title: String(localized: "Income"),
                           value: Money.string(snapshot.income, code: baseCurrency), valueTint: .income)
            }
            Divider().padding(.leading, 52)
            kindToggle(.expense) {
                summaryRow(symbol: "arrow.up.right", tint: Brand.expense, title: String(localized: "Expenses"),
                           value: Money.string(snapshot.expense, code: baseCurrency), valueTint: .primary)
            }
            Divider().padding(.leading, 52)
            summaryRow(symbol: "equal", tint: .gray, title: String(localized: "Net"),
                       subtitle: String(localized: "\(snapshot.count) transactions", comment: "Chart subtitle"),
                       value: Money.string(net, code: baseCurrency), valueTint: net >= 0 ? .income : Brand.expense)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func summaryRow(symbol: String, tint: Color, title: String, subtitle: String? = nil, value: String, valueTint: Color) -> some View {
        HStack(spacing: 12) {
            CategoryTile(symbol: symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    /// Tapping Income or Expenses narrows the list to that type (tap again to undo).
    private func kindToggle<Content: View>(_ kind: RecordKind, @ViewBuilder content: () -> Content) -> some View {
        let selected = router.transactionFilter.kinds == [kind]
        return Button {
            withAnimation(.snappy) { router.transactionFilter.kinds = selected ? [] : [kind] }
        } label: {
            content()
                .padding(.horizontal, 8)
                .background(selected ? Brand.accent.opacity(0.14) : .clear, in: .rect(cornerRadius: 12, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }

    private var activeFilters: some View {
        let filter = router.transactionFilter
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(filter.kinds), id: \.self) { kind in
                    Chip(title: kind.label, systemImage: "xmark", isSelected: true, tint: kind.tint) { router.transactionFilter.kinds.remove(kind) }
                }
                ForEach(Array(filter.accounts), id: \.self) { id in
                    if let account = accounts.first(where: { $0.uuid == id }) {
                        Chip(title: account.displayName, systemImage: "xmark", isSelected: true, tint: account.tint.color) { router.transactionFilter.accounts.remove(id) }
                    }
                }
                ForEach(Array(filter.categories).sorted(), id: \.self) { key in
                    let title = key.hasPrefix("group:") ? (RecordGroup(rawValue: String(key.dropFirst(6)))?.label ?? key) : RecordCategoryDisplay.resolve(key).label
                    Chip(title: title, systemImage: "xmark", isSelected: true, tint: .secondary) { router.transactionFilter.categories.remove(key) }
                }
                ForEach(Array(filter.labels).sorted(), id: \.self) { label in
                    Chip(title: label, systemImage: "xmark", isSelected: true, tint: LabelTint.color(for: label)) { router.transactionFilter.labels.remove(label) }
                }
                if let weekday = filter.weekday, Calendar.current.standaloneWeekdaySymbols.indices.contains(weekday - 1) {
                    Chip(title: Calendar.current.standaloneWeekdaySymbols[weekday - 1], systemImage: "xmark", isSelected: true, tint: .purple) { router.transactionFilter.weekday = nil }
                }
                if filter.trackedOnly {
                    Chip(title: String(localized: "Linked to items"), systemImage: "xmark", isSelected: true, tint: Brand.accent) { router.transactionFilter.trackedOnly = false }
                }
                Button("Clear all") {
                    withAnimation(.snappy) {
                        router.transactionFilter.accounts = []
                        router.transactionFilter.clearDetails()
                    }
                }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Derived data

private struct Snapshot {
    struct Day: Identifiable {
        let date: Date
        var records: [Record]
        var net: Double
        var id: Date { date }
    }

    let days: [Day]
    let income: Double
    let expense: Double
    let count: Int
    let hasMore: Bool
    let allLabels: [String]

    init(records: [Record], filter: TransactionFilter, search: String, limit: Int) {
        let interval = filter.interval()
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let numeric = CSV.number(query)
        var days: [Day] = []
        var income = 0.0, expense = 0.0, count = 0
        var labelCounts: [String: Int] = [:]

        for record in records {
            let flow = record.flow
            for label in flow.labels { labelCounts[label, default: 0] += 1 }
            guard filter.matches(flow, interval: interval) else { continue }
            if filter.trackedOnly && record.item == nil { continue }
            if !query.isEmpty {
                let hit = flow.note.localizedCaseInsensitiveContains(query)
                    || flow.payee.localizedCaseInsensitiveContains(query)
                    || flow.labels.contains { $0.localizedCaseInsensitiveContains(query) }
                    || flow.category.label.localizedCaseInsensitiveContains(query)
                    || (numeric.map { abs(flow.safeAmount - abs($0)) < 0.005 } ?? false)
                guard hit else { continue }
            }
            count += 1
            switch flow.kind {
            case .income: income += flow.baseAmount
            case .expense: expense += flow.baseAmount
            case .transfer: break
            }
            guard count <= limit else { continue }
            let day = flow.date.startOfDay
            if days.last?.date == day {
                days[days.count - 1].records.append(record)
                days[days.count - 1].net += flow.signedBase
            } else {
                days.append(Day(date: day, records: [record], net: flow.signedBase))
            }
        }
        self.days = days
        self.income = income
        self.expense = expense
        self.count = count
        self.hasMore = count > limit
        self.allLabels = labelCounts.sorted { $0.value > $1.value }.map(\.key)
    }
}

/// "Today · −NT$1,250" style day header.
struct DayHeader: View {
    let day: Date
    let net: Double
    let currency: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if abs(net) > 0.004 {
                Text((net < 0 ? "−" : "+") + Money.exact(abs(net), code: currency))
                    .monospacedDigit()
                    .foregroundStyle(net < 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.income))
            }
        }
        .font(.footnote.weight(.semibold))
        .textCase(nil)
    }

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Today", comment: "Period filter") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday", comment: "Day header") }
        if calendar.isDate(day, equalTo: .now, toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }
}
