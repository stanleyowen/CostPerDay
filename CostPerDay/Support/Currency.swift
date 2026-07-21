import Foundation

enum Currency {
    /// The currency new gadgets and totals default to, taken from the device region.
    static var deviceDefault: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    /// Every ISO code the system knows about, sorted so the likely ones come first.
    static let all: [String] = {
        let common = ["USD", "EUR", "GBP", "JPY", "TWD", "IDR", "CNY", "KRW", "HKD", "SGD", "AUD", "CAD", "CHF", "INR"]
        let rest = Locale.commonISOCurrencyCodes
            .filter { !common.contains($0) }
            .sorted()
        return common + rest
    }()

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    static func symbol(_ code: String) -> String {
        // `localizedString(forCurrencyCode:)` gives the name, not the glyph, so format a
        // zero and strip the digits out to recover whatever symbol the locale uses.
        let formatted = (0.0).formatted(.currency(code: code).precision(.fractionLength(0)))
        let stripped = formatted.filter { !$0.isNumber && !$0.isWhitespace && $0 != "." && $0 != "," }
        return stripped.isEmpty ? code : stripped
    }

    static func label(_ code: String) -> String {
        "\(code) — \(name(code))"
    }

    /// How many decimal places this currency actually uses — 0 for JPY/KRW, 2 for
    /// USD/EUR, 3 for a handful like BHD/KWD. Pinned to a fixed locale so the count
    /// tracks the currency itself, not whatever region the device happens to be set to.
    static func fractionDigits(_ code: String) -> Int {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.maximumFractionDigits
    }
}
