import SwiftUI
import SwiftData

/// Budget progress on Home.
struct BudgetsCard: View {
    let budgets: [Budget]
    let flows: [Flow]
    let excluded: Set<UUID>
    let currency: String

    var body: some View {
        let statuses = budgets.map { status(for: $0) }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardHeader(title: String(localized: "Budgets", comment: "Card title"))
                NavigationLink {
                    BudgetsView()
                } label: {
                    Text("Manage").font(.subheadline.weight(.medium))
                }
            }
            ForEach(statuses) { status in
                BudgetRow(status: status, currency: currency)
            }
        }
        .card()
    }

    private func status(for budget: Budget) -> BudgetStatus {
        BudgetStatus.evaluate(
            id: budget.uuid, name: budget.name, limit: budget.limit, period: budget.period,
            categoryKeys: budget.categoryKeys, flows: flows, excludedAccounts: excluded
        )
    }
}

struct BudgetRow: View {
    let status: BudgetStatus
    let currency: String

    private var tint: Color {
        status.isOver ? .red : status.isAhead ? .orange : .income
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.name.isEmpty ? String(localized: "Budget") : status.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Money.string(status.spent, code: currency)) of \(Money.string(status.limit, code: currency))")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .sensitive()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(8, geo.size.width * min(1, status.progress)))
                    // Where you'd be if spending were perfectly even across the period.
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 2, height: 14)
                        .offset(x: geo.size.width * status.elapsedFraction - 1)
                }
            }
            .frame(height: 10)
            Text(caption)
                .font(.caption)
                .foregroundStyle(status.isOver ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
        }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        if status.isOver {
            return String(localized: "Over by \(Money.string(-status.remaining, code: currency))", comment: "Budget status")
        }
        return String(localized: "\(Money.string(status.remaining, code: currency)) left · \(Money.string(status.dailyAllowance(), code: currency)) a day", comment: "Budget status")
    }
}

/// All budgets, with add/edit/delete.
struct BudgetsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @Query private var records: [Record]
    @Query private var accounts: [Account]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @State private var editing: Budget?
    @State private var adding = false

    var body: some View {
        let flows = records.map(\.flow)
        let excluded = Set(accounts.filter(\.excludeFromStats).map(\.uuid))
        List {
            if budgets.isEmpty {
                ContentUnavailableView {
                    Label("No budgets", systemImage: "target")
                } description: {
                    Text("Set a monthly limit for everything, or for the categories you want to keep an eye on.")
                } actions: {
                    Button("Create a budget") { adding = true }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                }
                .listRowBackground(Color.clear)
            }
            ForEach(budgets) { budget in
                Button {
                    editing = budget
                } label: {
                    BudgetRow(
                        status: BudgetStatus.evaluate(id: budget.uuid, name: budget.name, limit: budget.limit, period: budget.period, categoryKeys: budget.categoryKeys, flows: flows, excludedAccounts: excluded),
                        currency: baseCurrency
                    )
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets { context.delete(budgets[index]) }
                try? context.save()
            }
        }
        .navigationTitle("Budgets")
        .toolbar {
            Button("Add budget", systemImage: "plus") { adding = true }
        }
        .sheet(item: $editing) { BudgetEditView(budget: $0) }
        .sheet(isPresented: $adding) { BudgetEditView(budget: nil) }
    }
}

struct BudgetEditView: View {
    let budget: Budget?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @State private var draft: BudgetDraft

    init(budget: Budget?) {
        self.budget = budget
        _draft = State(initialValue: budget.map(BudgetDraft.init(budget:)) ?? BudgetDraft(name: "", limit: 0, period: .month, categoryKeys: []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text(defaultName))
                    HStack {
                        Text("Limit")
                        Spacer()
                        TextField("0", value: Binding(get: { draft.limit == 0 ? nil : draft.limit }, set: { draft.limit = $0 ?? 0 }), format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospacedDigit())
                        Text(baseCurrency).foregroundStyle(.secondary)
                    }
                    Picker("Period", selection: $draft.period) {
                        ForEach(BudgetPeriod.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    ForEach(RecordGroup.expenseGroups) { group in
                        let key = "group:" + group.rawValue
                        DisclosureGroup {
                            ForEach(RecordCategory.inGroup(group)) { category in
                                checkRow(category.label, symbol: category.symbol, tint: category.tint, key: category.rawValue)
                                    .disabled(draft.categoryKeys.contains(key))
                            }
                        } label: {
                            checkRow(group.label, symbol: group.symbol, tint: group.tint, key: key)
                        }
                    }
                } header: {
                    Text("Covers")
                } footer: {
                    Text(draft.categoryKeys.isEmpty ? "Nothing selected means the budget covers every expense." : "Only expenses in the selected categories count toward this budget.")
                }

                if let budget {
                    Section {
                        Button("Delete budget", role: .destructive) {
                            context.delete(budget)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(budget == nil ? String(localized: "New Budget", comment: "Screen title") : String(localized: "Edit Budget", comment: "Screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).disabled(!draft.isValid)
                }
            }
        }
    }

    private var defaultName: String {
        if draft.categoryKeys.count == 1, let key = draft.categoryKeys.first {
            return key.hasPrefix("group:") ? (RecordGroup(rawValue: String(key.dropFirst(6)))?.label ?? "") : RecordCategoryDisplay.resolve(key).label
        }
        return String(localized: "Spending", comment: "Default budget name")
    }

    private func checkRow(_ title: String, symbol: String, tint: Color, key: String) -> some View {
        let isOn = draft.categoryKeys.contains(key)
        return Button {
            if isOn { draft.categoryKeys.removeAll { $0 == key } } else { draft.categoryKeys.append(key) }
        } label: {
            HStack(spacing: 12) {
                CategoryTile(symbol: symbol, tint: tint, size: 28)
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isOn { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func save() {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { draft.name = defaultName }
        let target = budget ?? Budget()
        if budget == nil { context.insert(target) }
        draft.apply(to: target)
        try? context.save()
        dismiss()
    }
}

extension BudgetDraft {
    init(name: String, limit: Double, period: BudgetPeriod, categoryKeys: [String]) {
        self.name = name
        self.limit = limit
        self.period = period
        self.categoryKeys = categoryKeys
    }
}
