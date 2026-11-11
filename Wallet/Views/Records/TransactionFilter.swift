import SwiftUI

/// What the Transactions list is narrowed to. Empty sets mean "any".
struct TransactionFilter: Equatable {
    var period: PeriodPreset = .all
    var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    var customEnd: Date = .now
    var kinds: Set<RecordKind> = []
    var accounts: Set<UUID> = []
    /// Category keys, or `group:<raw>` for a whole group.
    var categories: Set<String> = []
    var labels: Set<String> = []
    /// `Calendar` weekday (1 = Sunday), set when drilling in from a report.
    var weekday: Int?
    var trackedOnly = false

    /// Not `self != TransactionFilter()`: the custom-range dates default to "now",
    /// so two untouched filters made a moment apart would never compare equal.
    var isActive: Bool { activeCount > 0 }

    var activeCount: Int {
        (period == .all ? 0 : 1) + (kinds.isEmpty ? 0 : 1) + (accounts.isEmpty ? 0 : 1)
            + (categories.isEmpty ? 0 : 1) + (labels.isEmpty ? 0 : 1) + (trackedOnly ? 1 : 0) + (weekday == nil ? 0 : 1)
    }

    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        period == .custom
            ? DateInterval(start: customStart.startOfDay, end: calendar.date(byAdding: .day, value: 1, to: customEnd.startOfDay) ?? customEnd)
            : period.interval(now: now, calendar: calendar)
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

enum PeriodPreset: String, CaseIterable, Identifiable {
    case all, today, thisWeek, thisMonth, lastMonth, last30, last90, thisYear, lastYear, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: String(localized: "All time", comment: "Period filter")
        case .today: String(localized: "Today", comment: "Period filter")
        case .thisWeek: String(localized: "This week", comment: "Period filter")
        case .thisMonth: String(localized: "This month", comment: "Period filter")
        case .lastMonth: String(localized: "Last month", comment: "Period filter")
        case .last30: String(localized: "Last 30 days", comment: "Period filter")
        case .last90: String(localized: "Last 90 days", comment: "Period filter")
        case .thisYear: String(localized: "This year", comment: "Period filter")
        case .lastYear: String(localized: "Last year", comment: "Period filter")
        case .custom: String(localized: "Custom range", comment: "Period filter")
        }
    }

    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        let today = now.startOfDay
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        switch self {
        case .all, .custom: return nil
        case .today: return DateInterval(start: today, end: tomorrow)
        case .thisWeek: return calendar.dateInterval(of: .weekOfYear, for: now)
        case .thisMonth: return calendar.dateInterval(of: .month, for: now)
        case .lastMonth:
            guard let anchor = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
            return calendar.dateInterval(of: .month, for: anchor)
        case .last30: return DateInterval(start: calendar.date(byAdding: .day, value: -29, to: today) ?? today, end: tomorrow)
        case .last90: return DateInterval(start: calendar.date(byAdding: .day, value: -89, to: today) ?? today, end: tomorrow)
        case .thisYear: return calendar.dateInterval(of: .year, for: now)
        case .lastYear:
            guard let anchor = calendar.date(byAdding: .year, value: -1, to: now) else { return nil }
            return calendar.dateInterval(of: .year, for: anchor)
        }
    }
}

/// Every filter dimension in one sheet.
struct TransactionFilterSheet: View {
    @Binding var filter: TransactionFilter
    let accounts: [Account]
    let labels: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Period") {
                    Picker("Period", selection: $filter.period) {
                        ForEach(PeriodPreset.allCases) { Text($0.label).tag($0) }
                    }
                    if filter.period == .custom {
                        DatePicker("From", selection: $filter.customStart, displayedComponents: .date)
                        DatePicker("To", selection: $filter.customEnd, in: filter.customStart..., displayedComponents: .date)
                    }
                }

                Section("Type") {
                    ForEach(RecordKind.allCases) { kind in
                        toggleRow(kind.label, symbol: kind.symbol, tint: kind.tint, isOn: filter.kinds.contains(kind)) {
                            filter.kinds.formSymmetricDifference([kind])
                        }
                    }
                }

                if !accounts.isEmpty {
                    Section("Accounts") {
                        ForEach(accounts) { account in
                            toggleRow(account.displayName, symbol: account.kind.symbol, tint: account.tint.color, isOn: filter.accounts.contains(account.uuid)) {
                                filter.accounts.formSymmetricDifference([account.uuid])
                            }
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
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { filter = TransactionFilter() }
                        .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sensoryFeedback(.selection, trigger: filter)
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
