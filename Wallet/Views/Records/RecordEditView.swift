import SwiftUI
import SwiftData

/// Adds or edits a transaction. Built for speed: a new transaction opens with the
/// decimal keyboard up on the amount, the note field suggests from your own history
/// and fills in category, account and usual amount, and Save is one tap away.
///
/// Tapping a transaction anywhere opens it here (there's no read-only screen), so
/// an existing transaction also gets everything you can do with one: its link to
/// a tracked item, Duplicate and Delete.
///
/// Binds to a `RecordDraft`, never the live `Record` — Cancel is a true no-op. The
/// item link is held the same way and only written on Update.
struct RecordEditView: View {
    /// Nil when creating.
    let record: Record?
    var onTrackItem: ((Item) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @Query(sort: \Account.sortOrder) private var accounts: [Account]
    @Query private var customCategories: [CustomCategory]

    @State private var draft: RecordDraft
    /// The amount as typed (see `AmountInput`), in the user's own notation.
    @State private var amountText: String
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
    /// The tracked item this transaction belongs to, and whether it's the purchase
    /// or upkeep. Edited here and written on Update, like the draft.
    @State private var linkedItem: Item?
    @State private var isItemPurchase: Bool
    @State private var choosingItem = false
    @State private var deleteRequest: DeleteRequest?
    /// What "unchanged" means: the draft once the editor has filled in its own
    /// defaults (account, category, currency). Nil until then.
    @State private var baseline: RecordDraft?
    @FocusState private var noteFocused: Bool
    @FocusState private var amountFocused: Bool

    init(record: Record?, prefill: RecordDraft? = nil, onTrackItem: ((Item) -> Void)? = nil) {
        self.record = record
        self.onTrackItem = onTrackItem
        let initial = record.map(RecordDraft.init(record:)) ?? prefill ?? RecordDraft()
        _draft = State(initialValue: initial)
        _amountText = State(initialValue: AmountInput.text(for: initial.amount, fractionDigits: Currency.fractionDigits(initial.currencyCode)))
        _received = State(initialValue: initial.toAmount > 0 ? initial.toAmount : nil)
        // A blank new entry hasn't chosen a category yet, so typing a familiar note may pick one.
        _categoryChosen = State(initialValue: record != nil || (prefill.map { $0.categoryKey != RecordCategory.unknown.rawValue } ?? false))
        _linkedItem = State(initialValue: record?.item)
        _isItemPurchase = State(initialValue: record?.isItemPurchase ?? false)
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

                    if let record {
                        if draft.kind == .expense || linkedItem != nil {
                            ownershipCard
                        }
                        infoCard(record)
                        actions(record)
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Save" : "Update") { save() }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        noteFocused = false
                        amountFocused = false
                    }
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
            .sheet(isPresented: $choosingItem) {
                ItemPickerSheet { item in
                    withAnimation(.snappy) {
                        linkedItem = item
                        isItemPurchase = false
                    }
                }
            }
            .deleteConfirmation($deleteRequest)
            .alert("Couldn't save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .sensoryFeedback(.error, trigger: invalidTrigger)
            .task { await loadContext() }
            .onChange(of: draft.kind) { old, new in kindChanged(from: old, to: new) }
            .onChange(of: draft.accountID) { _, _ in currencyMayHaveChanged() }
            .onChange(of: draft.toAccountID) { _, _ in currencyMayHaveChanged() }
            .onChange(of: draft.note) { _, note in applySuggestion(for: note) }
            .cancelAction(hasChanges: hasChanges) { dismiss() }
        }
    }

    private var title: String {
        switch (isNew, draft.kind) {
        case (true, .expense): String(localized: "New Expense", comment: "Screen title")
        case (true, .income): String(localized: "New Income", comment: "Screen title")
        case (true, .transfer): String(localized: "New Transfer", comment: "Screen title")
        case (false, _): String(localized: "Edit Transaction", comment: "Screen title")
        }
    }

    /// Anything the user changed since the editor opened. The amount and received
    /// fields live outside the draft until Save; the rate and currency follow the
    /// account, so they aren't edits of their own.
    private var hasChanges: Bool {
        guard let baseline else { return false }
        var current = draft
        current.amount = amountValue
        current.toAmount = received ?? 0
        current.rateToBase = baseline.rateToBase
        current.currencyCode = baseline.currencyCode
        return current != baseline || trackAsItem
            || linkedItem?.persistentModelID != record?.item?.persistentModelID
    }

    // MARK: Amount

    private var amountValue: Double { AmountInput.value(of: amountText) ?? 0 }

    /// The amount, typed on the system decimal keyboard.
    private var amountDisplay: some View {
        // Shrinks as the number grows, so long amounts still fit on one line.
        // (Counted with the grouping separators, which take room too.)
        let size: CGFloat = amountText.count > 12 ? 36 : amountText.count > 9 ? 44 : 54
        return VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: draft.kind == .expense ? "−" : draft.kind == .income ? "+" : "")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(draft.kind.tint)
                    .accessibilityHidden(true)
                TextField("Amount", text: $amountText, prompt: Text(verbatim: "0"))
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .fixedSize()
                Text(currency)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .animation(.snappy(duration: 0.2), value: size)

            if let rateNote {
                Text(rateNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        // Anywhere on the amount row puts the cursor in the field.
        .contentShape(.rect)
        .onTapGesture { amountFocused = true }
        .onChange(of: amountText) { _, text in
            let clean = AmountInput.sanitize(text, fractionDigits: Currency.fractionDigits(currency))
            if clean != text { amountText = clean }
        }
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
            if amountText.isEmpty, entry.typicalAmount > 0 {
                amountText = AmountInput.text(for: entry.typicalAmount, fractionDigits: Currency.fractionDigits(currency))
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
                CategoryTile(symbol: "shippingbox.fill", tint: Brand.accent, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Track as an owned item")
                        .font(.subheadline.weight(.semibold))
                    Text("Follow what this purchase costs per day for as long as you keep it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(Brand.accent)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
    }

    // MARK: Existing transaction

    /// The bridge to the ownership tracker: make this purchase a tracked item, file
    /// it as upkeep on one you already track, or see and unlink the one it's on.
    private var ownershipCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(
                title: String(localized: "Ownership", comment: "Card title"),
                subtitle: linkedItem == nil
                    ? String(localized: "Bought something that lasts? Track what it costs you per day.", comment: "Card subtitle")
                    : nil
            )
            if let item = linkedItem {
                let display = CategoryCatalog(custom: customCategories).display(for: item.categoryKey)
                NavigationLink {
                    ItemDetailView(item: item)
                } label: {
                    HStack(spacing: 12) {
                        ItemGlyph(category: display, progress: item.lifetimeProgress(), isRetired: item.isRetired, size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text(isItemPurchase
                                 ? String(localized: "Purchase", comment: "Role of a transaction linked to an item")
                                 : String(localized: "Upkeep", comment: "Role of a transaction linked to an item"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Brand.accent)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Money.perDay(item.totalCostPerDay(), code: baseCurrency))
                                .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                                .foregroundStyle(.primary)
                            Text("per day").font(.caption2).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Button("Unlink", systemImage: "xmark.circle") {
                    withAnimation(.snappy) {
                        linkedItem = nil
                        isItemPurchase = false
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    // Saves your edits first, then opens the new item to confirm.
                    Button {
                        trackAsItem = true
                        save()
                    } label: {
                        Label("Track as item", systemImage: "shippingbox.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    Button {
                        noteFocused = false
                        choosingItem = true
                    } label: {
                        Label("Add as upkeep", systemImage: "wrench.and.screwdriver.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
    }

    /// What the form doesn't edit: the payee and exchange rate recorded with the
    /// transaction, and where it came from.
    @ViewBuilder
    private func infoCard(_ record: Record) -> some View {
        let showsRate = record.currencyCode != baseCurrency
        let imported = record.importKey != nil
        if !record.payee.isEmpty || showsRate || imported {
            VStack(alignment: .leading, spacing: 0) {
                if !record.payee.isEmpty {
                    InfoRow("Payee", value: record.payee)
                }
                if showsRate {
                    if !record.payee.isEmpty { Divider() }
                    InfoRow("Rate", value: "1 \(record.currencyCode) = \(Flow.safeRate(record.rateToBase).formatted(.number.precision(.fractionLength(0...4)))) \(baseCurrency)")
                }
                if imported {
                    if !record.payee.isEmpty || showsRate { Divider() }
                    InfoRow("Source", value: String(localized: "Imported from BudgetBakers", comment: "Transaction source"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20, style: .continuous))
        }
    }

    private func actions(_ record: Record) -> some View {
        HStack(spacing: 10) {
            // Opens a new transaction prefilled from this one (as saved), dated now,
            // in this editor's place.
            Button {
                var copy = RecordDraft(record: record)
                copy.date = .now
                router.composer = copy
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 16))

            Button(role: .destructive) {
                noteFocused = false
                deleteRequest = .record(record, in: context) { dismiss() }
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .tint(.red)
        }
        .padding(.top, 4)
    }

    // MARK: Behaviour

    private func loadContext() async {
        // A new transaction starts with the amount, keyboard up.
        if isNew { amountFocused = true }
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
        var settled = draft
        settled.amount = amountValue
        settled.toAmount = received ?? 0
        baseline = settled
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
        let resized = AmountInput.sanitize(amountText, fractionDigits: digits)
        if resized != amountText { amountText = resized }
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
                if let value = AmountInput.value(of: amountText), destinationRate > 0 {
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
        noteFocused = false
        amountFocused = false
        draft.amount = amountValue
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
        if record == nil {
            context.insert(target)
        } else {
            target.item = linkedItem
            target.isItemPurchase = linkedItem != nil && isItemPurchase
        }
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
