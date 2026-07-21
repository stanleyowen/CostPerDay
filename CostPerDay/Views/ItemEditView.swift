import SwiftUI
import SwiftData

struct ItemEditView: View {
    @Bindable var item: Item
    let isNew: Bool

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

    private var issues: [ItemValidation.Issue] {
        ItemValidation.issues(for: item, baseCurrency: baseCurrency)
    }

    private var catalog: CategoryCatalog { CategoryCatalog(custom: customCategories) }
    private var category: CategoryDisplay { catalog.display(for: item.categoryKey) }

    private var isForeign: Bool { item.currencyCode != baseCurrency }

    /// Bridges the model's plain `Double` to an optional so a brand-new (zero)
    /// amount renders as an empty field with a placeholder, instead of a literal
    /// "0" the user has to select and delete before they can type.
    private var priceBinding: Binding<Double?> {
        Binding(get: { item.price == 0 ? nil : item.price }, set: { item.price = $0 ?? 0 })
    }

    private var resaleBinding: Binding<Double?> {
        Binding(get: { item.resaleValue == 0 ? nil : item.resaleValue }, set: { item.resaleValue = $0 ?? 0 })
    }

    private var lifetimeYears: Binding<Int> {
        Binding(
            get: { item.expectedLifetimeMonths / 12 },
            set: { item.expectedLifetimeMonths = clampLifetime($0 * 12 + item.expectedLifetimeMonths % 12) }
        )
    }

    private var lifetimeExtraMonths: Binding<Int> {
        Binding(
            get: { item.expectedLifetimeMonths % 12 },
            set: { item.expectedLifetimeMonths = clampLifetime(item.expectedLifetimeMonths / 12 * 12 + $0) }
        )
    }

    private func clampLifetime(_ months: Int) -> Int {
        min(max(months, 1), Item.maxLifetimeMonths)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $item.name)
                    fieldError(.name)
                    TextField("Brand (optional)", text: $item.brand)
                    NavigationLink {
                        CategoryPickerView(selectedKey: $item.categoryKey) { picked in
                            guard !lifetimeIsCustom else { return }
                            item.expectedLifetimeMonths = picked.defaultLifetimeMonths
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
                            format: .number.precision(.fractionLength(0...Currency.fractionDigits(item.currencyCode)))
                        )
                        .keyboardType(Currency.fractionDigits(item.currencyCode) > 0 ? .decimalPad : .numberPad)
                        .multilineTextAlignment(.trailing)
                    }
                    fieldError(.price)

                    Picker("Currency", selection: $item.currencyCode) {
                        ForEach(Currency.all, id: \.self) { code in
                            Text(Currency.label(code)).tag(code)
                        }
                    }
                    .onChange(of: item.currencyCode) { _, new in
                        rateQuote = nil
                        rateFetchError = nil
                        if new == baseCurrency {
                            // Same currency as your totals means no conversion at all.
                            item.rateToBase = 1
                        } else {
                            // The old rate belonged to a different currency pair — the
                            // moment the user picks a new one, go fetch a fresh rate.
                            Task { await fetchRate() }
                        }
                    }

                    DatePicker(
                        "Bought on",
                        selection: $item.purchaseDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    fieldError(.purchaseDate)
                }

                if isForeign {
                    Section {
                        LabeledContent("1 \(item.currencyCode) =") {
                            HStack(spacing: 4) {
                                TextField("Rate", value: $item.rateToBase, format: .number.precision(.fractionLength(0...6)))
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

                        if item.price > 0, item.rateToBase > 0 {
                            LabeledContent("Equivalent cost", value: Money.string(item.priceInBase, code: baseCurrency))
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Exchange rate")
                    } footer: {
                        Text("The rate is fixed at the time of purchase, so this item's cost does not change with the market. All totals are shown in \(baseCurrency).")
                    }
                }

                Section {
                    Stepper(value: $item.expectedLifetimeMonths, in: 1...Item.maxLifetimeMonths, step: 1) {
                        Button {
                            withAnimation { showLifetimeWheel.toggle() }
                        } label: {
                            LabeledContent(
                                "Expected to last",
                                value: Duration.fromMonths(item.expectedLifetimeMonths)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onChange(of: item.expectedLifetimeMonths) { lifetimeIsCustom = true }
                    fieldError(.lifetime)

                    if showLifetimeWheel {
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
                        .frame(height: 120)
                        .listRowInsets(EdgeInsets())
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                } header: {
                    Text("Expected lifetime")
                } footer: {
                    Text(showLifetimeWheel
                         ? "Use the wheel to select a value directly, or the stepper to adjust one month at a time."
                         : "Tap the value to select it directly, or use the stepper to adjust one month at a time.")
                    + Text(" The default for \(category.label) is \(Duration.fromMonths(category.defaultLifetimeMonths)).")
                }

                if item.price > 0 {
                    Section {
                        VerdictView(item: item, isNew: isNew, baseCurrency: baseCurrency)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Resale") {
                    LabeledContent("Recovered value") {
                        HStack(spacing: 4) {
                            Text(Currency.symbol(item.currencyCode))
                                .foregroundStyle(.secondary)
                            TextField(
                                "0", value: resaleBinding,
                                format: .number.precision(.fractionLength(0...Currency.fractionDigits(item.currencyCode)))
                            )
                            .keyboardType(Currency.fractionDigits(item.currencyCode) > 0 ? .decimalPad : .numberPad)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                    fieldError(.resale)
                    if isForeign, item.resaleValue > 0 {
                        LabeledContent("Rate when sold") {
                            HStack(spacing: 4) {
                                TextField("Same as purchase", value: $item.resaleRateToBase, format: .number.precision(.fractionLength(0...6)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                Text(baseCurrency).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Reason for purchase", text: $item.notes, axis: .vertical)
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
                    item.expectedLifetimeMonths = category.defaultLifetimeMonths
                    item.currencyCode = baseCurrency
                    item.rateToBase = 1
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
        item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.brand = item.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try context.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func cancel() {
        if isNew { context.delete(item) }
        dismiss()
    }

    @MainActor
    private func fetchRate() async {
        isFetchingRate = true
        defer { isFetchingRate = false }
        switch await ExchangeRateService.shared.quote(from: item.currencyCode, to: baseCurrency) {
        case .success(let quote):
            item.rateToBase = quote.rate
            rateQuote = quote
            rateFetchError = nil
        case .failure(let error):
            rateQuote = nil
            rateFetchError = error.localizedDescription
        }
    }
}

/// The deterrent. Shows the running cost in units small enough to feel honest
/// while you're still deciding whether to keep the entry.
private struct VerdictView: View {
    let item: Item
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
