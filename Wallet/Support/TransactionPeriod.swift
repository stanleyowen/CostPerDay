import Foundation

/// The stretch of time a transaction list covers, as the filter bar at the bottom
/// of every transaction list offers it: everything, a rolling window ending today
/// ("30 days"), a calendar period you can step through ("‹ This month ›"), or a
/// custom range of days.
enum TransactionPeriod: Hashable {
    case all
    case recent(RecentSpan)
    /// `offset` 0 is the current one, -1 the one before, and so on.
    case calendar(CalendarSpan, offset: Int)
    /// Whole days, both ends included.
    case custom(start: Date, end: Date)

    /// A rolling window that ends today.
    enum RecentSpan: CaseIterable, Hashable {
        case days7, days30, weeks12, months6, year1

        var label: String {
            switch self {
            case .days7: String(localized: "\(7) days")
            case .days30: String(localized: "\(30) days")
            case .weeks12: String(localized: "\(12) weeks", comment: "Rolling period in the transaction filter, e.g. '12 weeks'")
            case .months6: String(localized: "\(6) months")
            case .year1: String(localized: "\(1) years")
            }
        }

        fileprivate var length: (Calendar.Component, Int) {
            switch self {
            case .days7: (.day, 7)
            case .days30: (.day, 30)
            case .weeks12: (.weekOfYear, 12)
            case .months6: (.month, 6)
            case .year1: (.year, 1)
            }
        }
    }

    enum CalendarSpan: CaseIterable, Hashable {
        case day, week, month, year

        var component: Calendar.Component {
            switch self {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
        }

        /// The current one: "Today", "This week", …
        var currentLabel: String {
            switch self {
            case .day: String(localized: "Today", comment: "Period filter")
            case .week: String(localized: "This week", comment: "Period filter")
            case .month: String(localized: "This month", comment: "Period filter")
            case .year: String(localized: "This year", comment: "Period filter")
            }
        }
    }

    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        switch self {
        case .all:
            return nil
        case .recent(let span):
            let (component, count) = span.length
            // "7 days" is today and the six before it.
            let start = calendar.date(byAdding: component, value: -count, to: tomorrow) ?? today
            return DateInterval(start: start, end: tomorrow)
        case .calendar(let span, let offset):
            guard let anchor = calendar.date(byAdding: span.component, value: offset, to: now) else { return nil }
            return calendar.dateInterval(of: span.component, for: anchor)
        case .custom(let start, let end):
            let from = calendar.startOfDay(for: min(start, end))
            let lastDay = calendar.startOfDay(for: max(start, end))
            return DateInterval(start: from, end: calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay)
        }
    }

    /// One calendar period earlier (-1) or later (+1); never past the current one.
    func stepped(by delta: Int) -> TransactionPeriod {
        guard case .calendar(let span, let offset) = self else { return self }
        return .calendar(span, offset: min(0, offset + delta))
    }

    func label(now: Date = .now, calendar: Calendar = .current) -> String {
        switch self {
        case .all:
            return String(localized: "All time", comment: "Period filter")
        case .recent(let span):
            return span.label
        case .calendar(let span, 0):
            return span.currentLabel
        case .calendar(let span, let offset):
            guard let interval = interval(now: now, calendar: calendar) else { return "" }
            let sameYear = calendar.isDate(interval.start, equalTo: now, toGranularity: .year)
            switch (span, offset) {
            case (.day, -1): return String(localized: "Yesterday", comment: "Day header")
            case (.month, -1): return String(localized: "Last month", comment: "Period filter")
            case (.year, -1): return String(localized: "Last year", comment: "Period filter")
            case (.day, _):
                return interval.start.formatted(sameYear
                    ? .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                    : .dateTime.day().month(.abbreviated).year())
            case (.week, _):
                let last = interval.end.addingTimeInterval(-1)
                return (interval.start..<last).formatted(sameYear
                    ? .interval.day().month(.abbreviated)
                    : .interval.day().month(.abbreviated).year())
            case (.month, _):
                return interval.start.formatted(sameYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
            case (.year, _):
                return interval.start.formatted(.dateTime.year())
            }
        case .custom:
            guard let interval = interval(now: now, calendar: calendar) else { return "" }
            return (interval.start..<interval.end.addingTimeInterval(-1)).formatted(.interval.day().month(.abbreviated).year())
        }
    }
}
