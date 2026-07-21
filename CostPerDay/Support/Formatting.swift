import Foundation

enum Money {
    /// Whole-unit amounts: prices, totals. Large figures drop the cents — at three
    /// digits and up the decimals are noise.
    static func string(_ value: Double, code: String) -> String {
        guard value.isFinite else { return "—" }
        let digits = abs(value) >= 100 ? 0...0 : 0...2
        return value.formatted(.currency(code: code).precision(.fractionLength(digits)))
    }

    /// Per-day amounts are usually small, so they get more precision.
    static func perDay(_ value: Double, code: String) -> String {
        guard value.isFinite else { return "—" }
        let digits = abs(value) < 1 ? 2...3 : 2...2
        return value.formatted(.currency(code: code).precision(.fractionLength(digits)))
    }
}

enum Duration {
    /// "3 yr 2 mo", "8 mo", "12 days" — whichever reads best at that magnitude.
    static func fromDays(_ days: Int) -> String {
        if days < 60 { return "\(days) day\(days == 1 ? "" : "s")" }
        let months = Int((Double(days) / 30.4375).rounded())
        if months < 24 { return "\(months) mo" }
        let years = months / 12
        let remainder = months % 12
        return remainder == 0 ? "\(years) yr" : "\(years) yr \(remainder) mo"
    }

    static func fromMonths(_ months: Int) -> String {
        if months < 24 { return "\(months) month\(months == 1 ? "" : "s")" }
        let years = months / 12
        let remainder = months % 12
        return remainder == 0 ? "\(years) years" : "\(years) yr \(remainder) mo"
    }
}
