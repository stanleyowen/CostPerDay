import SwiftUI
import SwiftData

struct GadgetEditView: View {
    @Bindable var gadget: Gadget
    let isNew: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault

    /// Tracks whether the user has hand-picked a lifetime. Until they do, changing
    /// category keeps updating the lifetime to that category's sensible default.
    @State private var lifetimeIsCustom = false
    @State private var showAllIssues = false
    @State private var saveError: String?

    @State private var isFetchingRate = false
    @State private var rateQuote: ExchangeRateService.Quote?
    @State private var rateFetchError: String?

    private var issues: [GadgetValidation.Issue] {
        GadgetValidation.issues(for: gadget, baseCurrency: baseCurrency)
    }

    private var isForeign: Bool { gadget.currencyCode != baseCurrency }

    /// Bridges the model's plain `Double` to an optional so a brand-new (zero)
    /// amount renders as an empty field with a placeholder, instead of a literal
    /// "0" the user has to select and delete before they can type.
    private var priceBinding: Binding<Double?> {
        Binding(get: { gadget.price == 0 ? nil : gadget.price }, set: { gadget.price = $0 ?? 0 })
    }

    private var resaleBinding: Binding<Double?> {
        Binding(get: { gadget.resaleValue == 0 ? nil : gadget.resaleValue }, set: { gadget.resaleValue = $0 ?? 0 })
    }

    private var lifetimeYears: Binding<Int> {
        Binding(
            get: { gadget.expectedLifetimeMonths / 12 },
            set: { gadget.expectedLifetimeMonths = clampLifetime($0 * 12 + gadget.expectedLifetimeMonths % 12) }
        )
    }

    private var lifetimeExtraMonths: Binding<Int> {
        Binding(
            get: { gadget.expectedLifetimeMonths % 12 },
            set: { gadget.expectedLifetimeMonths = clampLifetime(gadget.expectedLifetimeMonths / 12 * 12 + $0) }
        )
    }

    private func clampLifetime(_ months: Int) -> Int {
        min(max(months, 1), Gadget.maxLifetimeMonths)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $gadget.name)
                    fieldError(.name)
                    TextField("Brand (optional)", text: $gadget.brand)
                    Picker("Category", selection: $gadget.category) {
                        ForEach(GadgetCategory.allCases) { category in
                            Label(category.label, systemImage: category.symbol).tag(category)
                        }
                    }
                    .onChange(of: gadget.category) { _, new in
                        guard !lifetimeIsCustom else { return }
                        gadget.expectedLifetimeMonths = new.defaultLifetimeMonths
                    }
                }

                Section("Purchase") {
                    LabeledContent("Price") {
                        HStack(spacing: 4) {
                            Text(Currency.symbol(gadget.currencyCode))
                                .foregroundStyle(.secondary)
                            TextField(
                                "0", value: priceBinding,
                                format: .number.precision(.fractionLength(0...Currency.fractionDigits(gadget.currencyCode)))
                            )
                            .keyboardType(Currency.fractionDigits(gadget.currencyCode) > 0 ? .decimalPad : .numberPad)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                    fieldError(.price)

                    Picker("Currency", selection: $gadget.currencyCode) {
                        ForEach(Currency.all, id: \.self) { code in
                            Text(Currency.label(code)).tag(code)
                        }
                    }
                    .onChange(of: gadget.currencyCode) { _, new in
                        rateQuote = nil
                        rateFetchError = nil
                        if new == baseCurrency {
                            // Same currency as your totals means no conversion at all.
                            gadget.rateToBase = 1
                        } else {
                            // The old rate belonged to a different currency pair — the
                            // moment the user picks a new one, go fetch a fresh rate.
                            Task { await fetchRate() }
                        }
                    }

                    DatePicker(
                        "Bought on",
                        selection: $gadget.purchaseDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                    fieldError(.purchaseDate)
                }

                if isForeign {
                    Section {
                        LabeledContent("1 \(gadget.currencyCode) =") {
                            HStack(spacing: 4) {
                                TextField("Rate", value: $gadget.rateToBase, format: .number.precision(.fractionLength(0...6)))
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
                                Text(isFetchingRate ? "Fetching rate…" : "Fetch today's rate")
                            }
                        }
                        .disabled(isFetchingRate)

                        if let quote = rateQuote {
                            Text(quote.servedFromCache
                                 ? "From a cached rate, \(quote.asOf.formatted(date: .abbreviated, time: .shortened))"
                                 : "Fetched just now")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let rateFetchError {
                            Text("\(rateFetchError) Enter the rate yourself.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if gadget.price > 0, gadget.rateToBase > 0 {
                            LabeledContent("Costs you", value: Money.string(gadget.priceInBase, code: baseCurrency))
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Exchange rate")
                    } footer: {
                        Text("Locked at the rate you paid, so this gadget's cost never shifts with the market. Your totals are shown in \(baseCurrency).")
                    }
                }

                Section {
                    Stepper(value: $gadget.expectedLifetimeMonths, in: 1...Gadget.maxLifetimeMonths, step: 1) {
                        LabeledContent(
                            "Expect it to last",
                            value: Duration.fromMonths(gadget.expectedLifetimeMonths)
                        )
                    }
                    .onChange(of: gadget.expectedLifetimeMonths) { lifetimeIsCustom = true }
                    fieldError(.lifetime)

                    HStack(spacing: 0) {
                        Picker("Years", selection: lifetimeYears) {
                            ForEach(0...Gadget.maxLifetimeMonths / 12, id: \.self) { year in
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
                } header: {
                    Text("Expected lifetime")
                } footer: {
                    Text("Scroll the wheel to jump to a value, or use the stepper for one month at a time. Default for \(gadget.category.label.lowercased()) is \(Duration.fromMonths(gadget.category.defaultLifetimeMonths)).")
                }

                if gadget.price > 0 {
                    Section {
                        VerdictView(gadget: gadget, isNew: isNew, baseCurrency: baseCurrency)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Resale") {
                    LabeledContent("Recovered value") {
                        HStack(spacing: 4) {
                            Text(Currency.symbol(gadget.currencyCode))
                                .foregroundStyle(.secondary)
                            TextField(
                                "0", value: resaleBinding,
                                format: .number.precision(.fractionLength(0...Currency.fractionDigits(gadget.currencyCode)))
                            )
                            .keyboardType(Currency.fractionDigits(gadget.currencyCode) > 0 ? .decimalPad : .numberPad)
                            .multilineTextAlignment(.trailing)
                        }
                    }
                    fieldError(.resale)
                    if isForeign, gadget.resaleValue > 0 {
                        LabeledContent("Rate when sold") {
                            HStack(spacing: 4) {
                                TextField("Same as purchase", value: $gadget.resaleRateToBase, format: .number.precision(.fractionLength(0...6)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                Text(baseCurrency).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Why did you buy it?", text: $gadget.notes, axis: .vertical)
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
            .navigationTitle(isNew ? "New Gadget" : "Edit Gadget")
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
                    gadget.expectedLifetimeMonths = gadget.category.defaultLifetimeMonths
                    gadget.currencyCode = baseCurrency
                    gadget.rateToBase = 1
                } else {
                    lifetimeIsCustom = true
                }
            }
        }
        .interactiveDismissDisabled(isNew)
    }

    @ViewBuilder
    private func fieldError(_ field: GadgetValidation.Field) -> some View {
        if showAllIssues, let message = GadgetValidation.message(for: field, in: issues) {
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
        gadget.name = gadget.name.trimmingCharacters(in: .whitespacesAndNewlines)
        gadget.brand = gadget.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try context.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func cancel() {
        if isNew { context.delete(gadget) }
        dismiss()
    }

    @MainActor
    private func fetchRate() async {
        isFetchingRate = true
        defer { isFetchingRate = false }
        switch await ExchangeRateService.shared.quote(from: gadget.currencyCode, to: baseCurrency) {
        case .success(let quote):
            gadget.rateToBase = quote.rate
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
    let gadget: Gadget
    let isNew: Bool
    let baseCurrency: String

    var body: some View {
        VStack(spacing: 10) {
            Text(isNew ? "This will cost you" : "Planned cost")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(Money.perDay(gadget.plannedCostPerDay, code: baseCurrency))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("every day for the next \(Duration.fromMonths(gadget.expectedLifetimeMonths))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                equivalent(Money.string(gadget.plannedCostPerDay * 7, code: baseCurrency), "a week")
                equivalent(Money.string(gadget.plannedCostPerDay * 30.4375, code: baseCurrency), "a month")
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
