import SwiftUI

/// What the Transactions list is narrowed to. Empty sets mean "any".
struct TransactionFilter: Equatable {
    var period: TransactionPeriod = .all
    var kinds: Set<RecordKind> = []
    var accounts: Set<UUID> = []
    /// Category keys, or `group:<raw>` for a whole group.
    var categories: Set<String> = []
    var labels: Set<String> = []
    /// `Calendar` weekday (1 = Sunday), set when drilling in from a report.
    var weekday: Int?
    var trackedOnly = false

    var isActive: Bool { activeCount > 0 }

    var activeCount: Int {
        (period == .all ? 0 : 1) + (accounts.isEmpty ? 0 : 1) + detailCount
    }

    /// Filters beyond period and accounts — the "More filters" row of the bar.
    var detailCount: Int {
        (kinds.isEmpty ? 0 : 1) + (categories.isEmpty ? 0 : 1) + (labels.isEmpty ? 0 : 1)
            + (trackedOnly ? 1 : 0) + (weekday == nil ? 0 : 1)
    }

    /// Everything except the period and accounts back to "any".
    mutating func clearDetails() {
        kinds = []
        categories = []
        labels = []
        weekday = nil
        trackedOnly = false
    }

    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        period.interval(now: now, calendar: calendar)
    }

    func matches(_ flow: Flow, interval: DateInterval?) -> Bool {
        if let interval, !(flow.date >= interval.start && flow.date < interval.end) { return false }
        if !kinds.isEmpty, !kinds.contains(flow.kind) { return false }
        if !accounts.isEmpty {
            let touches = flow.accountID.map(accounts.contains) == true || flow.toAccountID.map(accounts.contains) == true
            if !touches { return false }
        }
        if !categories.isEmpty {
            guard flow.kind != .transfer else { return false }
            if !categories.contains(flow.categoryKey) && !categories.contains("group:" + flow.category.group.rawValue) { return false }
        }
        if !labels.isEmpty, !flow.labels.contains(where: labels.contains) { return false }
        if let weekday, Calendar.current.component(.weekday, from: flow.date) != weekday { return false }
        return true
    }

    static func category(_ key: String) -> TransactionFilter {
        var filter = TransactionFilter()
        filter.categories = [key]
        return filter
    }
}

/// Every filter except the period, which has its own control above the list:
/// which accounts (`.all`, on the Transactions tab) and type, categories, labels
/// and items (`.details`, on an account's page, which is already one account).
struct TransactionFilterSheet: View {
    enum Part { case all, details }

    @Binding var filter: TransactionFilter
    let part: Part
    var accounts: [Account] = []
    var labels: [String] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if part == .all && !accounts.isEmpty {
                    Section {
                        ForEach(accounts) { account in
                            toggleRow(account.displayName, symbol: account.kind.symbol, tint: account.tint.color, isOn: filter.accounts.contains(account.uuid)) {
                                filter.accounts.formSymmetricDifference([account.uuid])
                            }
                        }
                    } header: {
                        Text("Accounts")
                    } footer: {
                        Text("None selected means every account.", comment: "Transaction filter: accounts footer")
                    }
                }
                details
            }
            .navigationTitle(String(localized: "Filter", comment: "Transaction filter sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Resets what this sheet shows; the period is left alone.
                    Button("Reset") {
                        if part == .all { filter.accounts = [] }
                        filter.clearDetails()
                    }
                    .disabled(Self.count(filter, part: part) == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sensoryFeedback(.selection, trigger: filter)
        }
    }

    /// How many filters this sheet holds are on — the badge on its button.
    static func count(_ filter: TransactionFilter, part: Part) -> Int {
        filter.detailCount + (part == .all && !filter.accounts.isEmpty ? 1 : 0)
    }

    @ViewBuilder
    private var details: some View {
        Section("Type") {
            ForEach(RecordKind.allCases) { kind in
                toggleRow(kind.label, symbol: kind.symbol, tint: kind.tint, isOn: filter.kinds.contains(kind)) {
                    filter.kinds.formSymmetricDifference([kind])
                }
            }
        }

        Section("Categories") {
            ForEach(RecordGroup.allCases) { group in
                DisclosureGroup {
                    ForEach(RecordCategory.inGroup(group)) { category in
                        toggleRow(category.label, symbol: category.symbol, tint: category.tint, isOn: filter.categories.contains(category.rawValue)) {
                            filter.categories.formSymmetricDifference([category.rawValue])
                        }
                    }
                } label: {
                    toggleRow(group.label, symbol: group.symbol, tint: group.tint, isOn: filter.categories.contains("group:" + group.rawValue)) {
                        filter.categories.formSymmetricDifference(["group:" + group.rawValue])
                    }
                }
            }
        }

        if !labels.isEmpty {
            Section("Labels") {
                ForEach(labels, id: \.self) { label in
                    toggleRow(label, symbol: "tag.fill", tint: LabelTint.color(for: label), isOn: filter.labels.contains(label)) {
                        filter.labels.formSymmetricDifference([label])
                    }
                }
            }
        }

        Section {
            Toggle("Only transactions linked to items", isOn: $filter.trackedOnly)
        }
    }

    private func toggleRow(_ title: String, symbol: String, tint: Color, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                CategoryTile(symbol: symbol, tint: tint, size: 28)
                Text(title).foregroundStyle(.primary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The toolbar button that opens the filter sheet, with how many filters are on.
struct FilterToolbarButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: count > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(Text("Filter", comment: "Transaction filter sheet title"))
        .badge(count)
        // A toolbar badge is drawn by the bar button underneath and isn't refreshed
        // when the count changes; tying the button's identity to the count rebuilds
        // it, badge included, whenever the count moves.
        .id(count)
    }
}
