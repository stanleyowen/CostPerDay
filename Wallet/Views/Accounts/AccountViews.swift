import SwiftUI
import SwiftData
import Charts

// MARK: - Editor

/// Creates or edits an account. Binds to `AccountDraft`; the live account is only
/// written on Save. For an existing account the balance field is the *current*
/// balance — what people actually know — and the opening balance is derived.
struct AccountEditView: View {
    let account: Account?
    var onCreate: ((Account) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @Query private var accounts: [Account]

    @State private var draft: AccountDraft
    @State private var balanceText: Double?
    @State private var recordedDelta: Double = 0
    @State private var choosingCurrency = false
    @State private var confirmingDelete = false
    @State private var recordCount = 0
    @State private var saveError: String?
    @FocusState private var nameFocused: Bool

    init(account: Account?, onCreate: ((Account) -> Void)? = nil) {
        self.account = account
        self.onCreate = onCreate
        let draft = account.map(AccountDraft.init(account:)) ?? AccountDraft(new: ())
        _draft = State(initialValue: draft)
    }

    private var isNew: Bool { account == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .frame(maxWidth: .infinity)
                }

                Section {
                    TextField("Account name", text: $draft.name)
                        .font(.body.weight(.medium))
                        .focused($nameFocused)
                    Button {
                        choosingCurrency = true
                    } label: {
                        HStack {
                            Text("Currency").foregroundStyle(.primary)
                            Spacer()
                            Text(Currency.label(draft.currencyCode)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .disabled(!isNew && recordCount > 0)
                    HStack {
                        Text(isNew ? "Starting balance" : "Current balance")
                        Spacer()
                        TextField("0", value: $balanceText, format: .number.precision(.fractionLength(0...Currency.fractionDigits(draft.currencyCode))))
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospacedDigit())
                    }
                } footer: {
                    if !isNew && recordCount > 0 {
                        Text("Currency can't change once an account has transactions. Correcting the balance adjusts the opening balance, so your history stays intact.")
                    }
                }

                Section("Type") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                        ForEach(AccountKind.allCases) { kind in
                            let selected = draft.kind == kind
                            Button {
                                withAnimation(.snappy) {
                                    if draft.tint == draft.kind.defaultTint { draft.tint = kind.defaultTint }
                                    draft.kind = kind
                                }
                            } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: kind.symbol).font(.title3)
                                    Text(kind.label).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                                .background(selected ? AnyShapeStyle(draft.tint.color.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .rect(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Colour") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(CategoryTint.allCases) { tint in
                            Button {
                                withAnimation(.snappy) { draft.tint = tint }
                            } label: {
                                Circle()
                                    .fill(tint.color.gradient)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if draft.tint == tint {
                                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(tint.label))
                            .accessibilityAddTraits(draft.tint == tint ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle("Exclude from statistics", isOn: $draft.excludeFromStats)
                    if !isNew {
                        Toggle("Archived", isOn: $draft.isArchived)
                    }
                } footer: {
                    Text("Excluded accounts still count toward your balance but not toward income and spending reports — useful for savings or investments. Archived accounts are hidden from pickers.")
                }

                if !isNew {
                    Section {
                        Button("Delete account", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? String(localized: "New Account", comment: "Screen title") : String(localized: "Edit Account", comment: "Screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $choosingCurrency) {
                CurrencyPickerView(selection: $draft.currencyCode)
            }
            .confirmationDialog(Text("Delete \(draft.name)?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete account and \(recordCount) transactions", role: .destructive, action: deleteAccount)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Transfers to and from other accounts are kept, marked as coming from outside Wallet. This can't be undone.")
            }
            .alert("Couldn't save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "") }
            .task { load() }
        }
    }

    private var preview: some View {
        let probe = Account(name: draft.name.isEmpty ? String(localized: "Account name") : draft.name, kind: draft.kind, currencyCode: draft.currencyCode, tint: draft.tint)
        return AccountCard(account: probe, balance: balanceText ?? 0, width: 240)
            .shadow(color: draft.tint.color.opacity(0.35), radius: 16, y: 8)
            .padding(.vertical, 8)
    }

    private func load() {
        if isNew {
            draft.currencyCode = draft.currencyCode.isEmpty ? baseCurrency : draft.currencyCode
            balanceText = nil
            nameFocused = true
            return
        }
        guard let account else { return }
        let id = account.uuid
        let records = (try? context.fetch(FetchDescriptor<Record>(predicate: #Predicate { $0.accountID == id || $0.toAccountID == id }))) ?? []
        recordCount = records.count
        let balance = Ledger.balances(accounts: [AccountRef(account)], flows: records.map(\.flow))[id] ?? account.initialBalance
        recordedDelta = balance - account.initialBalance
        balanceText = balance
    }

    private func save() {
        let entered = balanceText ?? 0
        draft.initialBalance = isNew ? entered : entered - recordedDelta
        let target = account ?? Account()
        if isNew {
            target.sortOrder = (accounts.map(\.sortOrder).max() ?? -1) + 1
            context.insert(target)
        }
        draft.apply(to: target)
        do {
            try context.save()
            if isNew { onCreate?(target) }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func deleteAccount() {
        guard let account else { return }
        let id = account.uuid
        let records = (try? context.fetch(FetchDescriptor<Record>(predicate: #Predicate { $0.accountID == id || $0.toAccountID == id }))) ?? []
        for record in records {
            if record.kind == .transfer {
                if record.accountID == id { record.accountID = nil }
                if record.toAccountID == id { record.toAccountID = nil }
                if record.accountID == nil && record.toAccountID == nil { context.delete(record) }
            } else {
                context.delete(record)
            }
        }
        context.delete(account)
        try? context.save()
        dismiss()
    }
}

extension AccountDraft {
    init(new: Void) {
        name = ""
        kind = .bank
        currencyCode = ""
        initialBalance = 0
        tint = AccountKind.bank.defaultTint
        isArchived = false
        excludeFromStats = false
    }
}

// MARK: - List

/// All accounts, reorderable, with total balance.
struct AccountsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var records: [Record]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @State private var editing: Account?
    @State private var adding = false

    var body: some View {
        let ledger = LedgerSnapshot(accounts: accounts, records: records, baseCurrency: baseCurrency)
        List {
            Section {
                HStack {
                    Text("Total balance").foregroundStyle(.secondary)
                    Spacer()
                    Text(Money.exact(ledger.netWorth, code: baseCurrency))
                        .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                }
            }
            Section {
                ForEach(ledger.accounts.filter { !$0.isArchived }) { account in
                    row(account, ledger: ledger)
                }
                .onMove { move($0, $1, among: ledger.accounts.filter { !$0.isArchived }) }
            }
            let archived = ledger.accounts.filter(\.isArchived)
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived) { row($0, ledger: ledger) }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add account", systemImage: "plus") { adding = true }
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(item: $editing) { AccountEditView(account: $0) }
        .sheet(isPresented: $adding) { AccountEditView(account: nil) }
    }

    private func row(_ account: Account, ledger: LedgerSnapshot) -> some View {
        NavigationLink {
            AccountDetailView(account: account)
        } label: {
            HStack(spacing: 12) {
                CategoryTile(symbol: account.kind.symbol, tint: account.tint.color, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName).font(.body.weight(.medium))
                    Text("\(account.kind.label) · \(account.currencyCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.exact(ledger.balance(of: account), code: account.currencyCode))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(ledger.balance(of: account) < 0 ? AnyShapeStyle(Brand.expense) : AnyShapeStyle(.primary))
            }
        }
        .swipeActions(edge: .leading) {
            Button("Edit", systemImage: "pencil") { editing = account }.tint(.blue)
        }
    }

    private func move(_ offsets: IndexSet, _ destination: Int, among list: [Account]) {
        var ordered = list
        ordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, account) in ordered.enumerated() { account.sortOrder = index }
        try? context.save()
    }
}

// MARK: - Detail

/// One account: balance, its trend, and its transactions.
struct AccountDetailView: View {
    let account: Account

    @Query private var records: [Record]
    @Query private var accounts: [Account]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @State private var editing = false
    @State private var composing = false

    init(account: Account) {
        self.account = account
        let id = account.uuid
        _records = Query(filter: #Predicate<Record> { $0.accountID == id || $0.toAccountID == id }, sort: \Record.date, order: .reverse)
    }

    var body: some View {
        let ledger = LedgerSnapshot(accounts: accounts, records: records, baseCurrency: baseCurrency)
        let balance = ledger.balance(of: account)
        let series = balanceSeries(ledger: ledger)

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        CategoryTile(symbol: account.kind.symbol, tint: account.tint.color, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.kind.label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            Text(Money.exact(balance, code: account.currencyCode))
                                .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                                .contentTransition(.numericText(value: balance))
                        }
                    }
                    if series.count > 1 {
                        balanceChart(series)
                    }
                }
                .padding(.vertical, 6)
            }

            if records.isEmpty {
                ContentUnavailableView("No transactions", systemImage: "list.bullet.rectangle", description: Text("Transactions in this account will appear here."))
            } else {
                ForEach(dayGroups) { group in
                    Section {
                        ForEach(group.records) { record in
                            let flow = record.flow
                            NavigationLink {
                                RecordDetailView(record: record)
                            } label: {
                                RecordRow(flow: flow, accountLine: ledger.accountLine(for: flow), linkedItemName: record.item?.displayName)
                            }
                        }
                    } header: {
                        Text(group.title)
                    }
                }
            }
        }
        .navigationTitle(account.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { editing = true }
        }
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            FloatingAddButton { composing = true }
        }
        .sheet(isPresented: $editing) { AccountEditView(account: account) }
        .sheet(isPresented: $composing) {
            RecordEditView(record: nil, prefill: RecordDraft(kind: .expense, accountID: account.uuid))
        }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let records: [Record]
        var id: Date { day }
        var title: String { day.formatted(date: .complete, time: .omitted) }
    }

    /// Capped to the most recent 300 so a long-lived account still opens instantly.
    private var dayGroups: [DayGroup] {
        Dictionary(grouping: records.prefix(300)) { $0.date.startOfDay }
            .map { DayGroup(day: $0.key, records: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    /// End-of-day balance over the last 90 days.
    private func balanceSeries(ledger: LedgerSnapshot) -> [(date: Date, value: Double)] {
        let calendar = Calendar.current
        let end = Date.now.startOfDay
        guard let start = calendar.date(byAdding: .day, value: -89, to: end) else { return [] }
        let ref = AccountRef(account)
        var running = Ledger.balances(accounts: [ref], flows: ledger.flows, upTo: start)[account.uuid] ?? account.initialBalance
        let inRange = ledger.flows.filter { $0.date >= start }.sorted { $0.date < $1.date }
        var index = 0
        var series: [(Date, Double)] = []
        for offset in 0..<90 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { continue }
            while index < inRange.count, inRange[index].date < next {
                for effect in Ledger.effects(of: inRange[index]) where effect.account == account.uuid {
                    running += effect.delta
                }
                index += 1
            }
            series.append((day, running))
        }
        return series
    }

    private func balanceChart(_ series: [(date: Date, value: Double)]) -> some View {
        TrendChart(series: series, tint: account.tint.color, lineColors: [account.tint.color],
                   currency: account.currencyCode, plotHeight: 160, spacing: 4) { focused in
            Text(focused.map { "\($0.date.formatted(.dateTime.day().month())) · \(Money.exact($0.value, code: account.currencyCode))" } ?? String(localized: "Last 90 days", comment: "Chart caption"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}
