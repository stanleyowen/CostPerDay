import Foundation

enum Money {
    /// Whole-unit amounts: prices, totals. Large figures drop the minor units — at three
    /// digits and up the decimals are noise.
    static func string(_ value: Double, code: String) -> String {
        guard value.isFinite else { return "—" }
        let digits = abs(value) >= 100 ? 0...0 : 0...2
        return value.formatted(.currency(code: code).precision(.fractionLength(digits)))
    }

    /// Per-day amounts are usually small, so they are given more precision.
    static func perDay(_ value: Double, code: String) -> String {
        guard value.isFinite else { return "—" }
        let digits = abs(value) < 1 ? 2...3 : 2...2
        return value.formatted(.currency(code: code).precision(.fractionLength(digits)))
    }
}

enum Duration {
    /// "3 yr 2 mo", "8 mo", "12 days" — whichever reads best at that magnitude.
    static func fromDays(_ days: Int) -> String {
        if days < 60 {
            return String(localized: "\(days) days", comment: "Duration in days, e.g. '12 days'")
        }
        let months = Int((Double(days) / 30.4375).rounded())
        return fromMonthsAbbreviated(months)
    }

    /// Abbreviated form used in dense contexts such as list rows.
    static func fromMonthsAbbreviated(_ months: Int) -> String {
        if months < 24 {
            return String(localized: "\(months) mo", comment: "Abbreviated duration in months, e.g. '8 mo'")
        }
        let years = months / 12
        let remainder = months % 12
        if remainder == 0 {
            return String(localized: "\(years) yr", comment: "Abbreviated duration in years, e.g. '3 yr'")
        }
        return String(localized: "\(years) yr \(remainder) mo", comment: "Abbreviated duration, e.g. '3 yr 2 mo'")
    }

    /// Spelled-out form used where there is room, such as form labels.
    static func fromMonths(_ months: Int) -> String {
        if months < 24 {
            return String(localized: "\(months) months", comment: "Duration in months, e.g. '18 months'")
        }
        let years = months / 12
        let remainder = months % 12
        if remainder == 0 {
            return String(localized: "\(years) years", comment: "Duration in years, e.g. '5 years'")
        }
        return String(localized: "\(years) yr \(remainder) mo", comment: "Abbreviated duration, e.g. '3 yr 2 mo'")
    }
}
