import SwiftUI
import SwiftData

struct ItemEditView: View {
    let item: Item
    let isNew: Bool

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
    @State private var showAllIssues = false
    @State private var saveError: String?

    @State private var isFetchingRate = false
    @State private var rateQuote: ExchangeRateService.Quote?
    @State private var rateFetchError: String?

    @State private var showLifetimeWheel = false

    init(item: Item, isNew: Bool) {
        self.item = item
        self.isNew = isNew
        _draft = State(initialValue: ItemDraft(item: item))
    }

    private var issues: [ItemValidation.Issue] {
        ItemValidation.issues(for: draft, baseCurrency: baseCurrency)
    }

    private var catalog: CategoryCatalog { CategoryCatalog(custom: customCategories) }
    private var category: CategoryDisplay { catalog.display(for: draft.categoryKey) }

    private var isForeign: Bool { draft.currencyCode != baseCurrency }

    /// Bridges the draft's plain `Double` to an optional so a brand-new (zero)
    /// amount renders as an empty field with a placeholder, instead of a literal
    /// "0" the user has to select and delete before they can type.
    private var priceBinding: Binding<Double?> {
        Binding(get: { draft.price == 0 ? nil : draft.price }, set: { draft.price = $0 ?? 0 })
    }

    private var resaleBinding: Binding<Double?> {
        Binding(get: { draft.resaleValue == 0 ? nil : draft.resaleValue }, set: { draft.resaleValue = $0 ?? 0 })
    }

    private var lifetimeYears: Binding<Int> {
        Binding(
            get: { draft.expectedLifetimeMonths / 12 },
            set: { draft.expectedLifetimeMonths = clampLifetime($0 * 12 + draft.expectedLifetimeMonths % 12) }
        )
    }

    private var lifetimeExtraMonths: Binding<Int> {
        Binding(
            get: { draft.expectedLifetimeMonths % 12 },
            set: { draft.expectedLifetimeMonths = clampLifetime(draft.expectedLifetimeMonths / 12 * 12 + $0) }
        )
    }

    private func clampLifetime(_ months: Int) -> Int {
        min(max(months, 1), Item.maxLifetimeMonths)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    fieldError(.name)
                    TextField("Brand (optional)", text: $draft.brand)
                    NavigationLink {
                        CategoryPickerView(selectedKey: $draft.categoryKey) { picked in
                            guard !lifetimeIsCustom else { return }
                            draft.expectedLifetimeMonths = picked.defaultLifetimeMonths
                        }
                    } label: {
                        // Deliberately a plain HStack, not LabeledContent — LabeledContent
                        // as a NavigationLink's label inflates the row to several times
                        // its normal height in a Form.
                        HStack {
                            Text("Category")
                            Spacer()
                            Label(category.label, systemImage: category.symbol)
                                .foregroundStyle(category.isMissing ? Color.secondary : category.tint)
                        }
                    }
                }

                Section("Purchase") {
                    LabeledContent("Price") {
                        // No currency symbol here — the Currency picker right below
                        // already says which currency this is in.
                        TextField(
                            "0", value: priceBinding,
                            format: .number.precision(.fractionLength(0...Currency.fractionDigits(draft.currencyCode)))
                        )
                        .keyboardType(Currency.fractionDigits(draft.currencyCode) > 0 ? .decimalPad : .numberPad)
                        .multilineTextAlignment(.trailing)
                    }
                    fieldError(.price)

                    Picker("Currency", selection: $draft.currencyCode) {
                        ForEach(Currency.all, id: \.self) { code in
                            Text(Currency.label(code)).tag(code)
                        }
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

                    DatePicker(
                        "Bought on",
                        selection: $draft.purchaseDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    fieldError(.purchaseDate)
                }

                if isForeign {
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

                Section {
                    Stepper(value: $draft.expectedLifetimeMonths, in: 1...Item.maxLifetimeMonths, step: 1) {
                        Button {
                            openLifetimeWheel()
                        } label: {
                            LabeledContent(
                                "Expected to last",
                                value: Duration.fromMonths(draft.expectedLifetimeMonths)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onChange(of: draft.expectedLifetimeMonths) { lifetimeIsCustom = true }
                    fieldError(.lifetime)
                } header: {
                    Text("Expected lifetime")
                } footer: {
                    Text(showLifetimeWheel
                         ? "Use the wheel to select a value directly, or the stepper to adjust one month at a time."
                         : "Tap the value to select it directly, or use the stepper to adjust one month at a time.")
                    + Text(" The default for \(category.label) is \(Duration.fromMonths(category.defaultLifetimeMonths)).")
                }

                if draft.price > 0 {
                    Section {
                        VerdictView(item: draft, isNew: isNew, baseCurrency: baseCurrency)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Resale") {
                    LabeledContent("Recovered value") {
                        HStack(spacing: 4) {
                            Text(Currency.symbol(draft.currencyCode))
                                .foregroundStyle(.secondary)
                            TextField(
                                "0", value: resaleBinding,
                                format: .number.precision(.fractionLength(0...Currency.fractionDigits(draft.currencyCode)))
                            )
                            .keyboardType(Currency.fractionDigits(draft.currencyCode) > 0 ? .decimalPad : .numberPad)
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

                Section("Notes") {
                    TextField("Reason for purchase", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...6)
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
            .safeAreaInset(edge: .bottom) {
                if showLifetimeWheel {
                    lifetimeWheelAccessory
                }
            }
            .navigationTitle(isNew ? String(localized: "New Item", comment: "Screen title") : String(localized: "Edit Item", comment: "Screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .alert("Couldn't save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .onAppear {
                if isNew {
                    draft.expectedLifetimeMonths = category.defaultLifetimeMonths
                    draft.currencyCode = baseCurrency
                    draft.rateToBase = 1
                } else {
                    lifetimeIsCustom = true
                }
            }
        }
        .interactiveDismissDisabled(isNew)
    }

    @ViewBuilder
    private func fieldError(_ field: ItemValidation.Field) -> some View {
        if showAllIssues, let message = ItemValidation.message(for: field, in: issues) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func save() {
        guard issues.isEmpty else {
            withAnimation { showAllIssues = true }
            return
        }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.brand = draft.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.apply(to: item)
        do {
            try context.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func cancel() {
        if isNew {
            // Never written to the draft-applied item at all — just discard the
            // insert made when this sheet was opened.
            context.delete(item)
            try? context.save()
        }
        dismiss()
    }

    /// Opens the lifetime wheel, dismissing any active text field first — the two
    /// shouldn't compete for the bottom of the screen at the same time.
    private func openLifetimeWheel() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.easeOut(duration: 0.25)) { showLifetimeWheel = true }
    }

    /// A picker that behaves like the keyboard: docked to the bottom of the screen,
    /// appearing only once the "Expected to last" row is tapped, dismissed with its
    /// own Done button rather than staying expanded inline in the form.
    private var lifetimeWheelAccessory: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Text("Expected lifetime")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Done") {
                    withAnimation(.easeIn(duration: 0.2)) { showLifetimeWheel = false }
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            HStack(spacing: 0) {
                Picker("Years", selection: lifetimeYears) {
                    ForEach(0...Item.maxLifetimeMonths / 12, id: \.self) { year in
                        Text("\(year) yr").tag(year)
                    }
                }
                .pickerStyle(.wheel)
                Picker("Months", selection: lifetimeExtraMonths) {
                    ForEach(0..<12, id: \.self) { month in
                        Text("\(month) mo").tag(month)
                    }
                }
                .pickerStyle(.wheel)
            }
            .frame(height: 200)
            .labelsHidden()
        }
        .background(.bar)
        .transition(.move(edge: .bottom))
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

/// The deterrent. Shows the running cost in units small enough to feel honest
/// while you're still deciding whether to keep the entry. Generic over `ItemFields`
/// so it can preview a live `Item` or, here, an in-progress `ItemDraft`.
private struct VerdictView<Fields: ItemFields>: View {
    let item: Fields
    let isNew: Bool
    let baseCurrency: String

    var body: some View {
        VStack(spacing: 10) {
            Text(isNew ? String(localized: "This will cost you", comment: "Heading above the projected daily cost of a new item") : String(localized: "Planned cost", comment: "Heading above the budgeted daily cost"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(Money.perDay(item.plannedCostPerDay, code: baseCurrency))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("per day over the next \(Duration.fromMonths(item.expectedLifetimeMonths))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                equivalent(Money.string(item.plannedCostPerDay * 7, code: baseCurrency), String(localized: "per week", comment: "Cost equivalence label"))
                equivalent(Money.string(item.plannedCostPerDay * 30.4375, code: baseCurrency), String(localized: "per month", comment: "Cost equivalence label"))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func equivalent(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.footnote.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
