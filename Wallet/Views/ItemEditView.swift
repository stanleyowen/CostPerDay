import SwiftUI
import SwiftData

struct ItemEditView: View {
    let item: Item
    let isNew: Bool
    /// A new item created from a transaction: price, currency, rate and date are
    /// already right, so the form keeps them instead of resetting to blanks.
    var prefilled = false

    /// The form edits this, never `item` directly — so Cancel can simply dismiss
    /// without needing to undo anything. `item` is only touched once, on Save.
    @State private var draft: ItemDraft

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @Query private var customCategories: [CustomCategory]

    /// Tracks whether the user has hand-picked a lifetime. Until they do, changing
    /// category keeps updating the lifetime to that category's sensible default.
    @State private var lifetimeIsCustom = false
    /// The last lifetime filled in automatically, so that change isn't mistaken for
    /// the user choosing one by hand.
    @State private var autoLifetime: Int?
    @State private var showAllIssues = false
    @State private var saveError: String?
    @State private var choosingCurrency = false
    @State private var savedTrigger = false
    @State private var invalidTrigger = 0

    @State private var isFetchingRate = false
    @State private var rateQuote: ExchangeRateService.Quote?
    @State private var rateFetchError: String?

    @FocusState private var focus: Field?
    private enum Field { case price, name }

    init(item: Item, isNew: Bool, prefilled: Bool = false) {
        self.item = item
        self.isNew = isNew
        self.prefilled = prefilled
        _draft = State(initialValue: ItemDraft(item: item))
    }

    private var issues: [ItemValidation.Issue] {
        ItemValidation.issues(for: draft, baseCurrency: baseCurrency)
    }

    private var catalog: CategoryCatalog { CategoryCatalog(custom: customCategories) }
    private var category: CategoryDisplay { catalog.display(for: draft.categoryKey) }
    private var isForeign: Bool { draft.currencyCode != baseCurrency }
    private var fractionDigits: Int { Currency.fractionDigits(draft.currencyCode) }

    /// Bridges the draft's plain `Double` to an optional so a brand-new (zero)
    /// amount renders as an empty field with a placeholder, instead of a literal
    /// "0" the user has to select and delete before they can type.
    private var priceBinding: Binding<Double?> {
        Binding(get: { draft.price == 0 ? nil : draft.price }, set: { draft.price = $0 ?? 0 })
    }

    private var resaleBinding: Binding<Double?> {
        Binding(get: { draft.resaleValue == 0 ? nil : draft.resaleValue }, set: { draft.resaleValue = $0 ?? 0 })
    }

    /// Resale only matters once something has been sold; hiding it for brand-new
    /// entries keeps the add flow to what's needed.
    private var showsResale: Bool { !isNew || draft.resaleValue > 0 }

    /// Quick picks for expected lifetime, plus the category's own default.
    private var lifetimePresets: [Int] {
        Array(Set([12, 24, 36, 60, 96, 120, category.defaultLifetimeMonths])).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                priceSection

                Section {
                    TextField("Name", text: $draft.name)
                        .font(.body.weight(.medium))
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                    fieldError(.name)
                    TextField("Brand (optional)", text: $draft.brand)
                    NavigationLink {
                        CategoryPickerView(selectedKey: $draft.categoryKey) { picked in
                            guard !lifetimeIsCustom else { return }
                            autoLifetime = picked.defaultLifetimeMonths
                            withAnimation { draft.expectedLifetimeMonths = picked.defaultLifetimeMonths }
                        }
                    } label: {
                        // Deliberately a plain HStack, not LabeledContent — LabeledContent
                        // as a NavigationLink's label inflates the row to several times
                        // its normal height in a Form.
                        HStack(spacing: 12) {
                            CategoryTile(symbol: category.symbol, tint: category.isMissing ? .secondary : category.tint, size: 30)
                            Text("Category")
                            Spacer()
                            Text(category.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("Bought on", selection: $draft.purchaseDate, in: ...Date.now, displayedComponents: .date)
                    fieldError(.purchaseDate)
                }

                if isForeign {
                    exchangeRateSection
                }

                lifetimeSection

                if showsResale {
                    Section("Resale") {
                        LabeledContent("Recovered value") {
                            HStack(spacing: 4) {
                                Text(Currency.symbol(draft.currencyCode))
                                    .foregroundStyle(.secondary)
                                TextField("0", value: resaleBinding, format: .number.precision(.fractionLength(0...fractionDigits)))
                                    .keyboardType(fractionDigits > 0 ? .decimalPad : .numberPad)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        fieldError(.resale)
                        if isForeign, draft.resaleValue > 0 {
                            LabeledContent("Rate when sold") {
                                HStack(spacing: 4) {
                                    TextField("Same as purchase", value: $draft.resaleRateToBase, format: .number.precision(.fractionLength(0...6)))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                    Text(baseCurrency).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Reason for purchase", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if showAllIssues, !issues.isEmpty {
                    Section {
                        ForEach(issues) { issue in
                            Label(issue.message, systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if draft.price > 0 {
                    VerdictBar(item: draft, isNew: isNew, baseCurrency: baseCurrency)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: draft.price > 0)
            .navigationTitle(isNew ? String(localized: "New Item", comment: "Screen title") : String(localized: "Edit Item", comment: "Screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            .alert("Couldn't save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .sheet(isPresented: $choosingCurrency) {
                CurrencyPickerView(selection: $draft.currencyCode)
            }
            .onChange(of: draft.currencyCode) { _, new in
                rateQuote = nil
                rateFetchError = nil
                if new == baseCurrency {
                    // Same currency as your totals means no conversion at all.
                    draft.rateToBase = 1
                } else {
                    // The old rate belonged to a different currency pair — the
                    // moment the user picks a new one, go fetch a fresh rate.
                    Task { await fetchRate() }
                }
            }
            .onAppear {
                if isNew && prefilled {
                    autoLifetime = draft.expectedLifetimeMonths
                    focus = .name
                } else if isNew {
                    autoLifetime = category.defaultLifetimeMonths
                    draft.expectedLifetimeMonths = category.defaultLifetimeMonths
                    draft.currencyCode = baseCurrency
                    draft.rateToBase = 1
                    focus = .price
                } else {
                    lifetimeIsCustom = true
                }
            }
            .sensoryFeedback(.success, trigger: savedTrigger)
            .sensoryFeedback(.error, trigger: invalidTrigger)
        }
        .interactiveDismissDisabled(isNew)
    }

    // MARK: Sections

    /// The amount is what people come here to type, so it leads — large, with the
    /// currency as a tappable chip right beside it.
    private var priceSection: some View {
        Section {
            VStack(spacing: 6) {
                Text("Price")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button {
                        focus = nil
                        choosingCurrency = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(draft.currencyCode)
                                .font(.system(.title3, design: .rounded).weight(.bold))
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.14), in: .capsule)
                        .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Currency"))
                    .accessibilityValue(Text(Currency.name(draft.currencyCode)))

                    TextField("0", value: priceBinding, format: .number.precision(.fractionLength(0...fractionDigits)))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .keyboardType(fractionDigits > 0 ? .decimalPad : .numberPad)
                        .focused($focus, equals: .price)
                        .minimumScaleFactor(0.5)
                        .accessibilityLabel(Text("Price"))
                }
                .frame(maxWidth: .infinity)
                fieldError(.price)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
    }

    private var exchangeRateSection: some View {
        Section {
            LabeledContent("1 \(draft.currencyCode) =") {
                HStack(spacing: 4) {
                    TextField("Rate", value: $draft.rateToBase, format: .number.precision(.fractionLength(0...6)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text(baseCurrency).foregroundStyle(.secondary)
                }
            }
            fieldError(.rate)

            Button {
                Task { await fetchRate() }
            } label: {
                HStack {
                    if isFetchingRate {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isFetchingRate ? String(localized: "Retrieving rate…", comment: "Shown while an exchange rate is being fetched") : String(localized: "Retrieve today's rate", comment: "Button to fetch the current exchange rate"))
                }
            }
            .disabled(isFetchingRate)

            if let quote = rateQuote {
                Text(quote.servedFromCache
                     ? String(localized: "From a cached rate of \(quote.asOf.formatted(date: .abbreviated, time: .shortened))", comment: "Shown under an exchange rate field. The placeholder is a date and time.")
                     : String(localized: "Retrieved just now", comment: "Shown under an exchange rate field"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let rateFetchError {
                Text("\(rateFetchError) Please enter the rate manually.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if draft.price > 0, draft.rateToBase > 0 {
                LabeledContent("Equivalent cost", value: Money.string(draft.priceInBase, code: baseCurrency))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Exchange rate")
        } footer: {
            Text("The rate is fixed at the time of purchase, so this item's cost does not change with the market. All totals are shown in \(baseCurrency).")
        }
    }

    private var lifetimeSection: some View {
        Section {
            Stepper(value: $draft.expectedLifetimeMonths, in: 1...Item.maxLifetimeMonths, step: 1) {
                HStack {
                    Text("Expected to last")
                    Spacer()
                    Text(Duration.fromMonths(draft.expectedLifetimeMonths))
                        .font(.body.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText(value: Double(draft.expectedLifetimeMonths)))
                }
            }
            .onChange(of: draft.expectedLifetimeMonths) { _, new in
                if new != autoLifetime { lifetimeIsCustom = true }
            }
            fieldError(.lifetime)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(lifetimePresets, id: \.self) { months in
                        Chip(
                            title: Duration.fromMonthsAbbreviated(months),
                            systemImage: months == category.defaultLifetimeMonths ? category.symbol : nil,
                            isSelected: draft.expectedLifetimeMonths == months
                        ) {
                            withAnimation(.snappy) { draft.expectedLifetimeMonths = months }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
            .sensoryFeedback(.selection, trigger: draft.expectedLifetimeMonths)
        } header: {
            Text("Expected lifetime")
        } footer: {
            Text(String(localized: " The default for \(category.label) is \(Duration.fromMonths(category.defaultLifetimeMonths)).")
                .trimmingCharacters(in: .whitespaces))
        }
    }

    @ViewBuilder
    private func fieldError(_ field: ItemValidation.Field) -> some View {
        if showAllIssues, let message = ItemValidation.message(for: field, in: issues) {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: Actions

    private func save() {
        guard issues.isEmpty else {
            withAnimation { showAllIssues = true }
            invalidTrigger += 1
            return
        }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.brand = draft.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.apply(to: item)
        do {
            try context.save()
            savedTrigger.toggle()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func cancel() {
        if isNew {
            // Never written to the draft-applied item at all — just discard the
            // insert made when this sheet was opened. A transaction it was created
            // from goes back to being an ordinary transaction.
            for record in item.records ?? [] { record.isItemPurchase = false }
            context.delete(item)
            try? context.save()
        }
        dismiss()
    }

    @MainActor
    private func fetchRate() async {
        isFetchingRate = true
        defer { isFetchingRate = false }
        switch await ExchangeRateService.shared.quote(from: draft.currencyCode, to: baseCurrency) {
        case .success(let quote):
            draft.rateToBase = quote.rate
            rateQuote = quote
            rateFetchError = nil
        case .failure(let error):
            rateQuote = nil
            rateFetchError = error.localizedDescription
        }
    }
}

/// The deterrent, pinned to the bottom of the form and updated with every keystroke:
/// what this purchase works out to per day, week and month. Generic over `ItemFields`
/// so it previews the in-progress draft without touching the live record.
private struct VerdictBar<Fields: ItemFields>: View {
    let item: Fields
    let isNew: Bool
    let baseCurrency: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text(isNew ? String(localized: "This will cost you", comment: "Heading above the projected daily cost of a new item") : String(localized: "Planned cost", comment: "Heading above the budgeted daily cost"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Money.perDay(item.plannedCostPerDay, code: baseCurrency))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: item.plannedCostPerDay))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("per day")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.amber)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                equivalent(Money.string(item.plannedCostPerDay * 7, code: baseCurrency), CostPeriod.week.label)
                equivalent(Money.string(item.plannedCostPerDay * 30.4375, code: baseCurrency), CostPeriod.month.label)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(HeroBackground())
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .animation(.snappy, value: item.plannedCostPerDay)
        .accessibilityElement(children: .combine)
    }

    private func equivalent(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
    }
}
