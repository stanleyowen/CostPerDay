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

/// The filters behind the bar's rows: which accounts, or everything else (type,
/// categories, labels, items). The period lives on the bar itself.
struct TransactionFilterSheet: View {
    enum Part { case accounts, details }

    @Binding var filter: TransactionFilter
    let part: Part
    var accounts: [Account] = []
    var labels: [String] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if part == .accounts {
                    Section {
                        ForEach(accounts) { account in
                            toggleRow(account.displayName, symbol: account.kind.symbol, tint: account.tint.color, isOn: filter.accounts.contains(account.uuid)) {
                                filter.accounts.formSymmetricDifference([account.uuid])
                            }
                        }
                    } footer: {
                        Text("None selected means every account.", comment: "Transaction filter: accounts footer")
                    }
                } else {
                    details
                }
            }
            .navigationTitle(part == .accounts ? String(localized: "Accounts") : String(localized: "More filters", comment: "Transaction filter sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        if part == .accounts { filter.accounts = [] } else { filter.clearDetails() }
                    }
                    .disabled(part == .accounts ? filter.accounts.isEmpty : filter.detailCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sensoryFeedback(.selection, trigger: filter)
        }
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
