import SwiftUI
import SwiftData

/// Adds or edits a transaction. Built for speed: the amount keypad is always on
/// screen, the note field suggests from your own history and fills in category,
/// account and usual amount, and Save is one tap away.
///
/// Binds to a `RecordDraft`, never the live `Record` — Cancel is a true no-op.
struct RecordEditView: View {
    /// Nil when creating.
    let record: Record?
    var onTrackItem: ((Item) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    @State private var draft: RecordDraft
    @State private var expression: AmountExpression
    @State private var received: Double?
    @State private var categoryChosen: Bool
    @State private var suggestions = SuggestionIndex.empty
    @State private var allLabels: [String] = []
    @State private var trackAsItem = false
    @State private var choosingCategory = false
    @State private var choosingLabels = false
    @State private var addingAccount = false
    @State private var rateNote: String?
    @State private var saveError: String?
    @State private var invalidTrigger = 0
    @State private var keyTrigger = 0
    @FocusState private var noteFocused: Bool

    init(record: Record?, prefill: RecordDraft? = nil, onTrackItem: ((Item) -> Void)? = nil) {
        self.record = record
        self.onTrackItem = onTrackItem
        let initial = record.map(RecordDraft.init(record:)) ?? prefill ?? RecordDraft()
        _draft = State(initialValue: initial)
        _expression = State(initialValue: AmountExpression(value: initial.amount, maxFractionDigits: Currency.fractionDigits(initial.currencyCode)))
        _received = State(initialValue: initial.toAmount > 0 ? initial.toAmount : nil)
        // A blank new entry hasn't chosen a category yet, so typing a familiar note may pick one.
        _categoryChosen = State(initialValue: record != nil || (prefill.map { $0.categoryKey != RecordCategory.unknown.rawValue } ?? false))
    }

    private var isNew: Bool { record == nil }
    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived || $0.uuid == draft.accountID || $0.uuid == draft.toAccountID } }
    private func account(_ id: UUID?) -> Account? { id.flatMap { id in accounts.first { $0.uuid == id } } }
    private var source: Account? { account(draft.accountID) }
    private var destination: Account? { account(draft.toAccountID) }
    private var currency: String { source?.currencyCode ?? destination?.currencyCode ?? draft.currencyCode }
    private var isCrossCurrency: Bool {
        draft.kind == .transfer && source != nil && destination != nil && source?.currencyCode != destination?.currencyCode
    }
    private var category: RecordCategoryDisplay {
        draft.kind == .transfer ? .transfer : RecordCategoryDisplay.resolve(draft.categoryKey)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    KindPicker(kind: $draft.kind)
                        .padding(.horizontal, 4)

                    amountDisplay

                    if accounts.isEmpty {
                        noAccountsCard
                    } else {
                        detailsCard
                    }

                    if !suggestionMatches.isEmpty && (noteFocused || draft.note.isEmpty) {
                        suggestionStrip
                    }

                    if draft.kind == .expense && isNew {
                        trackToggle
                    }

                    if let issue = draft.issues.first, invalidTrigger > 0 {
                        Label(message(for: issue), systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.red)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !noteFocused {
                    AmountKeypad(
                        expression: $expression,
                        accent: draft.kind.tint,
                        saveTitle: isNew ? String(localized: "Save", comment: "Button") : String(localized: "Update", comment: "Button"),
                        onKey: { keyTrigger += 1 },
                        onSave: save
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: noteFocused)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Save" : "Update") { save() }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { noteFocused = false }
                }
            }
            .sheet(isPresented: $choosingCategory) {
                RecordCategoryPicker(
                    kind: draft.kind,
                    selection: Binding(get: { draft.categoryKey }, set: { draft.categoryKey = $0; categoryChosen = true }),
                    frequent: suggestions.frequentCategories(kind: draft.kind)
                )
            }
            .sheet(isPresented: $choosingLabels) {
                LabelPicker(selection: $draft.labels, known: allLabels)
            }
            .sheet(isPresented: $addingAccount) {
                AccountEditView(account: nil) { created in
                    draft.accountID = created.uuid
                }
            }
            .alert("Couldn't save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: keyTrigger)
            .sensoryFeedback(.error, trigger: invalidTrigger)
            .task { await loadContext() }
            .onChange(of: draft.kind) { old, new in kindChanged(from: old, to: new) }
            .onChange(of: draft.accountID) { _, _ in currencyMayHaveChanged() }
            .onChange(of: draft.toAccountID) { _, _ in currencyMayHaveChanged() }
            .onChange(of: draft.note) { _, note in applySuggestion(for: note) }
        }
        .interactiveDismissDisabled(isDirty)
    }

    private var title: String {
        switch (isNew, draft.kind) {
        case (true, .expense): String(localized: "New Expense", comment: "Screen title")
        case (true, .income): String(localized: "New Income", comment: "Screen title")
        case (true, .transfer): String(localized: "New Transfer", comment: "Screen title")
        case (false, _): String(localized: "Edit Transaction", comment: "Screen title")
        }
    }

    private var isDirty: Bool {
        let original = record.map(RecordDraft.init(record:))
        return (expression.value ?? 0) != (original?.amount ?? 0) || draft.note != (original?.note ?? "")
    }

    // MARK: Amount

    private var amountDisplay: some View {
        let value = expression.value ?? 0
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: draft.kind == .expense ? "−" : draft.kind == .income ? "+" : "")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(draft.kind.tint)
                Text(value.formatted(.number.precision(.fractionLength(0...Currency.fractionDigits(currency)))))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
                    .foregroundStyle(expression.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(currency)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .animation(.snappy(duration: 0.2), value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Amount"))
            .accessibilityValue(Text(Money.exact(value, code: currency)))

            if expression.hasOperator {
                Text(verbatim: expression.text)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            } else if let rateNote {
                Text(rateNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: Details

    private var detailsCard: some View {
        VStack(spacing: 0) {
            if draft.kind == .transfer {
                accountRow(title: String(localized: "From", comment: "Transfer source"), selection: $draft.accountID, allowsOutside: true)
                Divider().padding(.leading, 56)
                accountRow(title: String(localized: "To", comment: "Transfer destination"), selection: $draft.toAccountID, allowsOutside: true)
                if isCrossCurrency, let destination {
                    Divider().padding(.leading, 56)
                    receivedRow(destination)
                }
            } else {
                accountRow(title: String(localized: "Account", comment: "Field label"), selection: $draft.accountID, allowsOutside: false)
                Divider().padding(.leading, 56)
                categoryRow
            }
            Divider().padding(.leading, 56)
            dateRow
            Divider().padding(.leading, 56)
            noteRow
            Divider().padding(.leading, 56)
            labelsRow
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func accountRow(title: String, selection: Binding<UUID?>, allowsOutside: Bool) -> some View {
        let selected = account(selection.wrappedValue)
        return Menu {
            ForEach(activeAccounts) { account in
                Button {
                    selection.wrappedValue = account.uuid
                } label: {
                    Label("\(account.displayName) · \(account.currencyCode)", systemImage: account.kind.symbol)
                }
            }
            if allowsOutside {
                Divider()
                Button {
                    selection.wrappedValue = nil
                } label: {
                    Label("Outside Wallet", systemImage: "arrow.up.forward.square")
                }
            }
            Divider()
            Button("New account…", systemImage: "plus") { addingAccount = true }
        } label: {
            FieldRow(
                symbol: selected?.kind.symbol ?? "arrow.up.forward.square",
                tint: selected?.tint.color ?? .gray,
                title: title,
                value: selected?.displayName ?? (allowsOutside
                    ? String(localized: "Outside Wallet", comment: "Transfer endpoint that isn't a tracked account")
                    : String(localized: "Choose", comment: "Placeholder for an unselected picker")),
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
    }

    private func receivedRow(_ destination: Account) -> some View {
        HStack(spacing: 12) {
            CategoryTile(symbol: "arrow.down.left", tint: .income, size: 32)
            Text("Received")
            Spacer()
            TextField("0", value: $received, format: .number.precision(.fractionLength(0...Currency.fractionDigits(destination.currencyCode))))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(maxWidth: 140)
            Text(destination.currencyCode).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var categoryRow: some View {
        Button {
            noteFocused = false
            choosingCategory = true
        } label: {
            FieldRow(
                symbol: category.symbol,
                tint: category.tint,
                title: String(localized: "Category", comment: "Field label"),
                value: categoryChosen || draft.categoryKey != RecordCategory.unknown.rawValue
                    ? category.label
                    : String(localized: "Choose", comment: "Placeholder for an unselected picker"),
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
    }

    private var dateRow: some View {
        HStack(spacing: 12) {
            CategoryTile(symbol: "calendar", tint: .red, size: 32)
            DatePicker("Date", selection: $draft.date, in: ...Date.now.addingTimeInterval(86_400 * 366))
                .datePickerStyle(.compact)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var noteRow: some View {
        HStack(spacing: 12) {
            CategoryTile(symbol: "text.alignleft", tint: .gray, size: 32)
            TextField("Note (optional)", text: $draft.note, axis: .vertical)
                .lineLimit(1...4)
                .focused($noteFocused)
                .submitLabel(.done)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var labelsRow: some View {
        Button {
            noteFocused = false
            choosingLabels = true
        } label: {
            HStack(spacing: 12) {
                CategoryTile(symbol: "tag.fill", tint: .teal, size: 32)
                if draft.labels.isEmpty {
                    Text("Labels").foregroundStyle(.primary)
                    Spacer()
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LabelChips(labels: draft.labels)
                    }
                    Spacer(minLength: 0)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var noAccountsCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "building.columns")
                .font(.title2)
                .foregroundStyle(.tint)
            Text("Add an account first")
                .font(.headline)
            Text("Transactions belong to an account — a bank account, a cash pocket, a card.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add account") { addingAccount = true }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
        .card()
    }

    // MARK: Suggestions

    private var suggestionMatches: [SuggestionIndex.Entry] {
        guard draft.kind != .transfer else { return [] }
        let matches = suggestions.matches(draft.note, kind: draft.kind)
        // Once the note exactly matches a suggestion there's nothing left to suggest.
        if matches.count == 1, matches[0].note.caseInsensitiveCompare(draft.note) == .orderedSame { return [] }
        return matches
    }

    private var suggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestionMatches) { entry in
                    let display = RecordCategoryDisplay.resolve(entry.categoryKey)
                    Button {
                        use(entry)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: display.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(display.tint)
                            Text(entry.note)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            if entry.typicalAmount > 0 {
                                Text(entry.typicalAmount.formatted(.number.precision(.fractionLength(0...2))))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    private func use(_ entry: SuggestionIndex.Entry) {
        withAnimation(.snappy) {
            draft.note = entry.note
            draft.categoryKey = entry.categoryKey
            categoryChosen = true
            if let accountID = entry.accountID, accounts.contains(where: { $0.uuid == accountID && !$0.isArchived }) {
                draft.accountID = accountID
            }
            if expression.isEmpty, entry.typicalAmount > 0 {
                expression = AmountExpression(value: entry.typicalAmount, maxFractionDigits: Currency.fractionDigits(currency))
            }
        }
        noteFocused = false
    }

    /// Typing a note you've used before picks its usual category — unless you've
    /// already chosen one yourself.
    private func applySuggestion(for note: String) {
        guard !categoryChosen, draft.kind != .transfer, let key = suggestions.category(note: note) else { return }
        withAnimation(.snappy) { draft.categoryKey = key }
    }

    // MARK: Track as item

    private var trackToggle: some View {
        Toggle(isOn: $trackAsItem.animation(.snappy)) {
            HStack(spacing: 12) {
                CategoryTile(symbol: "shippingbox.fill", tint: Brand.ember, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Track as an owned item")
                        .font(.subheadline.weight(.semibold))
                    Text("Follow what this purchase costs per day for as long as you keep it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(Brand.ember)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
    }

    // MARK: Behaviour

    private func loadContext() async {
        if isNew && draft.accountID == nil && draft.toAccountID == nil {
            draft.accountID = LedgerActions.defaultAccount(in: context)?.uuid
        }
        currencyMayHaveChanged()
        // Learn from recent history for suggestions; capped so it stays instant.
        var descriptor = FetchDescriptor<Record>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 3_000
        let recent = (try? context.fetch(descriptor)) ?? []
        let flows = recent.map(\.flow)
        suggestions = SuggestionIndex(flows: flows)
        var labelCounts: [String: Int] = [:]
        for flow in flows { for label in flow.labels { labelCounts[label, default: 0] += 1 } }
        allLabels = labelCounts.sorted { $0.value > $1.value }.map(\.key)
        if isNew, !categoryChosen, draft.kind != .transfer, draft.categoryKey == RecordCategory.unknown.rawValue,
           let top = suggestions.frequentCategories(kind: draft.kind, limit: 1).first {
            // Pre-select the most common category, but keep it visibly "suggested".
            draft.categoryKey = top
        }
    }

    private func kindChanged(from old: RecordKind, to new: RecordKind) {
        if new == .income, RecordCategory(rawValue: draft.categoryKey)?.isIncome != true {
            draft.categoryKey = suggestions.frequentCategories(kind: .income, limit: 1).first ?? RecordCategory.incomeGeneral.rawValue
            categoryChosen = false
        } else if new == .expense, RecordCategory(rawValue: draft.categoryKey)?.isIncome == true {
            draft.categoryKey = suggestions.frequentCategories(kind: .expense, limit: 1).first ?? RecordCategory.unknown.rawValue
            categoryChosen = false
        }
        if new == .transfer, draft.toAccountID == nil {
            draft.toAccountID = activeAccounts.first { $0.uuid != draft.accountID }?.uuid
        }
        if new != .transfer, draft.accountID == nil {
            draft.accountID = draft.toAccountID ?? activeAccounts.first?.uuid
        }
    }

    private func currencyMayHaveChanged() {
        let code = currency
        let digits = Currency.fractionDigits(code)
        if expression.maxFractionDigits != digits {
            expression = AmountExpression(value: expression.value ?? 0, maxFractionDigits: digits)
        }
        guard code != draft.currencyCode || (isNew && code != baseCurrency && rateNote == nil) else { return }
        draft.currencyCode = code
        if code == baseCurrency {
            draft.rateToBase = 1
            rateNote = nil
            return
        }
        Task {
            let rate = await LedgerActions.rate(for: code, baseCurrency: baseCurrency, context: context)
            draft.rateToBase = rate
            rateNote = "1 \(code) = \(rate.formatted(.number.precision(.fractionLength(0...4)))) \(baseCurrency)"
            if isCrossCurrency, received == nil, let destination {
                let destinationRate = await LedgerActions.rate(for: destination.currencyCode, baseCurrency: baseCurrency, context: context)
                if let value = expression.value, destinationRate > 0 {
                    received = (value * rate / destinationRate * 100).rounded() / 100
                }
            }
        }
    }

    private func message(for issue: RecordDraft.Issue) -> String {
        switch issue {
        case .noAmount: String(localized: "Enter an amount.", comment: "Validation message")
        case .noAccount: String(localized: "Choose an account.", comment: "Validation message")
        case .sameAccount: String(localized: "Choose two different accounts.", comment: "Validation message")
        case .noDestination: String(localized: "Choose where the money went.", comment: "Validation message")
        }
    }

    private func save() {
        expression.collapse()
        draft.amount = expression.value ?? 0
        draft.currencyCode = currency
        if draft.kind == .transfer {
            draft.toAmount = isCrossCurrency ? (received ?? 0) : 0
        }
        if draft.kind != .transfer, draft.categoryKey.isEmpty {
            draft.categoryKey = RecordCategory.unknown.rawValue
        }
        guard draft.issues.isEmpty else {
            withAnimation { invalidTrigger += 1 }
            return
        }

        let target = record ?? Record()
        draft.apply(to: target)
        if record == nil { context.insert(target) }
        var trackedItem: Item?
        if trackAsItem && draft.kind == .expense {
            trackedItem = LedgerActions.trackAsItem(target, in: context)
        }
        do {
            try context.save()
            dismiss()
            if let trackedItem { onTrackItem?(trackedItem) }
        } catch {
            saveError = error.localizedDescription
        }
    }
}

extension RecordDraft {
    /// A blank new transaction.
    init(kind: RecordKind = .expense, accountID: UUID? = nil, date: Date = .now) {
        self.kind = kind
        amount = 0
        currencyCode = Currency.deviceDefault
        rateToBase = 1
        self.date = date
        self.accountID = accountID
        toAccountID = nil
        toAmount = 0
        categoryKey = kind == .income ? RecordCategory.incomeGeneral.rawValue : RecordCategory.unknown.rawValue
        note = ""
        payee = ""
        labels = []
    }
}

// MARK: - Pieces

/// An icon, a label and a value — the rows of the transaction form.
struct FieldRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let value: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryTile(symbol: symbol, tint: tint, size: 32)
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}

/// Calculator-style keypad. Long-press ⌫ to clear.
struct AmountKeypad: View {
    @Binding var expression: AmountExpression
    let accent: Color
    let saveTitle: String
    let onKey: () -> Void
    let onSave: () -> Void

    private let rows: [[Character]] = [
        ["7", "8", "9", "÷"],
        ["4", "5", "6", "×"],
        ["1", "2", "3", "−"],
        [".", "0", "⌫", "+"],
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
            // While a sum is being typed this is "=", so the result can be checked
            // before saving; otherwise it saves.
            Button {
                if expression.hasOperator {
                    expression.collapse()
                    onKey()
                } else {
                    onSave()
                }
            } label: {
                Text(expression.hasOperator ? "=" : saveTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(accent.gradient, in: .rect(cornerRadius: 16, style: .continuous))
                    .contentTransition(.interpolate)
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    @ViewBuilder
    private func keyButton(_ key: Character) -> some View {
        let isOperator = AmountExpression.operators.contains(key)
        Button {
            if key == "⌫" { expression.backspace() } else { expression.input(key) }
            onKey()
        } label: {
            Group {
                if key == "⌫" {
                    Image(systemName: "delete.left")
                } else {
                    Text(String(key))
                }
            }
            .font(.system(size: isOperator ? 22 : 24, weight: isOperator ? .semibold : .medium, design: .rounded))
            .foregroundStyle(isOperator ? AnyShapeStyle(accent) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                isOperator ? AnyShapeStyle(accent.opacity(0.12)) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                in: .rect(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(accessibilityName(key))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            if key == "⌫" { expression.clear(); onKey() }
        })
    }

    private func accessibilityName(_ key: Character) -> Text {
        switch key {
        case "⌫": Text("Delete")
        case "+": Text("Plus")
        case "−": Text("Minus")
        case "×": Text("Times")
        case "÷": Text("Divided by")
        case ".": Text("Decimal point")
        default: Text(verbatim: String(key))
        }
    }
}
