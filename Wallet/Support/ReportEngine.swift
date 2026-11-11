import Foundation

/// The span a report covers.
enum ReportRange: String, CaseIterable, Identifiable, Sendable {
    case week, month, quarter, year, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: String(localized: "Week", comment: "Report range")
        case .month: String(localized: "Month", comment: "Report range")
        case .quarter: String(localized: "Quarter", comment: "Report range")
        case .year: String(localized: "Year", comment: "Report range")
        case .all: String(localized: "All", comment: "Report range: all time")
        }
    }

    var component: Calendar.Component? {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        case .all: nil
        }
    }

    /// How finely the cash-flow chart slices this range.
    var bucket: Calendar.Component {
        switch self {
        case .week, .month: .day
        case .quarter: .weekOfYear
        case .year, .all: .month
        }
    }
}

/// A concrete, navigable period: "November 2026", "Week of 9 Nov", "2025".
struct ReportPeriod: Hashable, Sendable {
    let range: ReportRange
    let interval: DateInterval

    static func containing(_ date: Date, range: ReportRange, earliest: Date? = nil, calendar: Calendar = .current) -> ReportPeriod {
        if let component = range.component {
            let interval = calendar.dateInterval(of: component, for: date)
                ?? quarterInterval(containing: date, calendar: calendar)
            return ReportPeriod(range: range, interval: interval)
        }
        let start = (earliest ?? date).startOfDay
        let end = calendar.date(byAdding: .day, value: 1, to: max(date, start).startOfDay) ?? date
        return ReportPeriod(range: .all, interval: DateInterval(start: min(start, end), end: end))
    }

    /// Foundation doesn't always answer `.quarter` intervals, so compute it directly.
    private static func quarterInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let startMonth = ((month - 1) / 3) * 3 + 1
        let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? date.startOfDay
        let end = calendar.date(byAdding: .month, value: 3, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    func shifted(by steps: Int, calendar: Calendar = .current) -> ReportPeriod {
        guard range != .all, let component = range.component else { return self }
        let unit: Calendar.Component = component == .quarter ? .month : component
        let amount = component == .quarter ? steps * 3 : steps
        let anchor = calendar.date(byAdding: unit, value: amount, to: interval.start) ?? interval.start
        return .containing(anchor, range: range, calendar: calendar)
    }

    var previous: ReportPeriod? { range == .all ? nil : shifted(by: -1) }

    func contains(_ date: Date) -> Bool { date >= interval.start && date < interval.end }

    /// Days in the period that have actually happened, for honest daily averages.
    func elapsedDays(now: Date = .now, calendar: Calendar = .current) -> Int {
        let end = min(interval.end, max(interval.start, calendar.date(byAdding: .day, value: 1, to: now.startOfDay) ?? now))
        let days = calendar.dateComponents([.day], from: interval.start, to: end).day ?? 0
        return max(1, days)
    }

    var title: String {
        let start = interval.start
        switch range {
        case .week:
            let end = interval.end.addingTimeInterval(-1)
            return "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
        case .month:
            return start.formatted(.dateTime.month(.wide).year())
        case .quarter:
            return start.formatted(.dateTime.quarter().year())
        case .year:
            return start.formatted(.dateTime.year())
        case .all:
            return String(localized: "All time", comment: "Report period title")
        }
    }

    /// The chart buckets covering this period.
    func buckets(calendar: Calendar = .current) -> [DateInterval] {
        var component = range.bucket
        if range == .all {
            let years = calendar.dateComponents([.year], from: interval.start, to: interval.end).year ?? 0
            if years >= 4 { component = .year }
        }
        var result: [DateInterval] = []
        var cursor = calendar.dateInterval(of: component, for: interval.start)?.start ?? interval.start
        while cursor < interval.end, result.count < 400 {
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            result.append(DateInterval(start: cursor, end: next))
            cursor = next
        }
        return result
    }
}

/// Everything the Reports screen shows for one period, computed in a single pass.
struct Report: Sendable {
    struct Slice: Identifiable, Hashable, Sendable {
        let key: String
        let total: Double
        let count: Int
        var id: String { key }
    }

    struct Bucket: Identifiable, Hashable, Sendable {
        let start: Date
        let end: Date
        var income: Double
        var expense: Double
        var id: Date { start }
        var net: Double { income - expense }
    }

    let period: ReportPeriod
    let income: Double
    let expense: Double
    let incomeCount: Int
    let expenseCount: Int
    let previousIncome: Double?
    let previousExpense: Double?
    /// Expense by category key, largest first.
    let expenseByCategory: [Slice]
    /// Expense by `RecordGroup` raw value, largest first.
    let expenseByGroup: [Slice]
    let incomeByCategory: [Slice]
    let byLabel: [Slice]
    /// Expense per account UUID string.
    let expenseByAccount: [Slice]
    let buckets: [Bucket]
    /// Expense per calendar day (start of day).
    let dailyExpense: [Date: Double]
    /// Mean expense per weekday, Sunday = index 0.
    let weekdayExpense: [Double]
    let largestExpenses: [Flow]
    let averageDailyExpense: Double

    var net: Double { income - expense }
    var transactionCount: Int { incomeCount + expenseCount }

    /// Share of income kept, or nil when there was no income to keep.
    var savingsRate: Double? { income > 0 ? (income - expense) / income : nil }

    func change(current: Double, previous: Double?) -> Double? {
        guard let previous, previous > 0.005 else { return nil }
        return (current - previous) / previous
    }

    var expenseChange: Double? { change(current: expense, previous: previousExpense) }
    var incomeChange: Double? { change(current: income, previous: previousIncome) }

    static func build(
        flows: [Flow],
        period: ReportPeriod,
        excludedAccounts: Set<UUID> = [],
        accountFilter: UUID? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Report {
        func counts(_ flow: Flow) -> Bool {
            guard flow.kind != .transfer else { return false }
            if let id = flow.accountID, excludedAccounts.contains(id) { return false }
            if let accountFilter, flow.accountID != accountFilter { return false }
            return true
        }

        var income = 0.0, expense = 0.0, incomeCount = 0, expenseCount = 0
        var previousIncome = 0.0, previousExpense = 0.0
        var byCategory: [String: (Double, Int)] = [:]
        var byGroup: [String: (Double, Int)] = [:]
        var incomeByCategory: [String: (Double, Int)] = [:]
        var byLabel: [String: (Double, Int)] = [:]
        var byAccount: [String: (Double, Int)] = [:]
        var daily: [Date: Double] = [:]
        var expenses: [Flow] = []

        let previous = period.previous
        // While a period is still running, compare it with the same stretch of the
        // previous one ("1–11 Nov vs 1–11 Oct"), not with a whole finished period.
        var previousEnd = previous?.interval.end ?? .distantPast
        if let previous, period.contains(now) {
            previousEnd = min(previousEnd, previous.interval.start.addingTimeInterval(now.timeIntervalSince(period.interval.start)))
        }
        var bucketList = period.buckets(calendar: calendar).map { Bucket(start: $0.start, end: $0.end, income: 0, expense: 0) }

        for flow in flows where counts(flow) {
            if let previous, previous.contains(flow.date) {
                guard flow.date < previousEnd else { continue }
                if flow.kind == .income { previousIncome += flow.baseAmount } else { previousExpense += flow.baseAmount }
                continue
            }
            guard period.contains(flow.date) else { continue }
            let value = flow.baseAmount
            if let index = bucketIndex(for: flow.date, in: bucketList) {
                if flow.kind == .income { bucketList[index].income += value } else { bucketList[index].expense += value }
            }
            if flow.kind == .income {
                income += value
                incomeCount += 1
                incomeByCategory[flow.categoryKey, default: (0, 0)].0 += value
                incomeByCategory[flow.categoryKey, default: (0, 0)].1 += 1
            } else {
                expense += value
                expenseCount += 1
                expenses.append(flow)
                byCategory[flow.categoryKey, default: (0, 0)].0 += value
                byCategory[flow.categoryKey, default: (0, 0)].1 += 1
                let group = flow.category.group.rawValue
                byGroup[group, default: (0, 0)].0 += value
                byGroup[group, default: (0, 0)].1 += 1
                if let account = flow.accountID?.uuidString {
                    byAccount[account, default: (0, 0)].0 += value
                    byAccount[account, default: (0, 0)].1 += 1
                }
                for label in flow.labels {
                    byLabel[label, default: (0, 0)].0 += value
                    byLabel[label, default: (0, 0)].1 += 1
                }
                daily[calendar.startOfDay(for: flow.date), default: 0] += value
            }
        }

        // Average per weekday over the weeks the period actually covered so far.
        var weekdayTotals = Array(repeating: 0.0, count: 7)
        var weekdayDays = Array(repeating: 0, count: 7)
        let elapsed = period.elapsedDays(now: now, calendar: calendar)
        for offset in 0..<min(elapsed, 3_700) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: period.interval.start) else { continue }
            let weekday = calendar.component(.weekday, from: day) - 1
            weekdayDays[weekday] += 1
            weekdayTotals[weekday] += daily[calendar.startOfDay(for: day)] ?? 0
        }
        let weekdayMeans = zip(weekdayTotals, weekdayDays).map { $1 > 0 ? $0 / Double($1) : 0 }

        func slices(_ dict: [String: (Double, Int)]) -> [Slice] {
            dict.map { Slice(key: $0.key, total: $0.value.0, count: $0.value.1) }
                .sorted { $0.total == $1.total ? $0.key < $1.key : $0.total > $1.total }
        }

        let hasPrevious = previous != nil
        return Report(
            period: period,
            income: income,
            expense: expense,
            incomeCount: incomeCount,
            expenseCount: expenseCount,
            previousIncome: hasPrevious ? previousIncome : nil,
            previousExpense: hasPrevious ? previousExpense : nil,
            expenseByCategory: slices(byCategory),
            expenseByGroup: slices(byGroup),
            incomeByCategory: slices(incomeByCategory),
            byLabel: slices(byLabel),
            expenseByAccount: slices(byAccount),
            buckets: bucketList,
            dailyExpense: daily,
            weekdayExpense: weekdayMeans,
            largestExpenses: Array(expenses.sorted { $0.baseAmount > $1.baseAmount }.prefix(5)),
            averageDailyExpense: expense / Double(elapsed)
        )
    }

    /// Buckets are sorted and contiguous, so binary search.
    private static func bucketIndex(for date: Date, in buckets: [Bucket]) -> Int? {
        var low = 0, high = buckets.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if date < buckets[mid].start { high = mid - 1 }
            else if date >= buckets[mid].end { low = mid + 1 }
            else { return mid }
        }
        return nil
    }
}

// MARK: - Budgets

struct BudgetStatus: Identifiable, Sendable {
    let id: UUID
    let name: String
    let limit: Double
    let spent: Double
    let interval: DateInterval
    let elapsedFraction: Double

    var remaining: Double { limit - spent }
    var progress: Double { limit > 0 ? spent / limit : 0 }
    var isOver: Bool { spent > limit }
    /// Spending faster than the calendar: more than the elapsed share of the period
    /// already gone (with a little slack so day one isn't an instant warning).
    var isAhead: Bool { !isOver && progress > elapsedFraction + 0.1 }
    /// What can still be spent per remaining day without going over.
    func dailyAllowance(now: Date = .now, calendar: Calendar = .current) -> Double {
        let days = max(1, calendar.dateComponents([.day], from: now.startOfDay, to: interval.end).day ?? 1)
        return max(0, remaining) / Double(days)
    }

    static func evaluate(
        id: UUID, name: String, limit: Double, period: BudgetPeriod, categoryKeys: [String],
        flows: [Flow], excludedAccounts: Set<UUID> = [], now: Date = .now, calendar: Calendar = .current
    ) -> BudgetStatus {
        let interval = period.interval(containing: now, calendar: calendar)
        let keys = Set(categoryKeys)
        let groups = Set(categoryKeys.compactMap { $0.hasPrefix("group:") ? String($0.dropFirst(6)) : nil })
        let spent = flows.reduce(0.0) { total, flow in
            guard flow.kind == .expense, flow.date >= interval.start, flow.date < interval.end else { return total }
            if let account = flow.accountID, excludedAccounts.contains(account) { return total }
            if !keys.isEmpty {
                let matches = keys.contains(flow.categoryKey) || groups.contains(flow.category.group.rawValue)
                if !matches { return total }
            }
            return total + flow.baseAmount
        }
        let elapsed = now.timeIntervalSince(interval.start) / max(1, interval.duration)
        return BudgetStatus(
            id: id, name: name, limit: limit, spent: spent, interval: interval,
            elapsedFraction: min(1, max(0, elapsed))
        )
    }
}
