import Foundation

/// The amount field in the transaction editor: plain text typed on the system
/// decimal keyboard, kept to a well-formed number in the user's own notation and
/// grouped as it's typed ("1234567" reads "1,234,567"), so long amounts stay
/// legible.
enum AmountInput {
    /// Digits grouped in thousands (the locale's way, so en_IN gets "12,34,567"),
    /// one decimal separator, and no more decimals than the currency has. The
    /// locale's grouping marks are ignored when reading what's there; any other
    /// "." or "," counts as the decimal point, the last one if there are several.
    static func sanitize(_ text: String, fractionDigits: Int, locale: Locale = .current) -> String {
        let separator = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        let stripped = text.filter { !grouping.contains($0) && !$0.isWhitespace }
        let marks: Set<Character> = [".", ",", Character(separator)]
        let lastMark = stripped.lastIndex { marks.contains($0) }
        var whole = "", fraction = "", hasSeparator = false
        for index in stripped.indices {
            let character = stripped[index]
            if character.isASCII, character.isNumber {
                if hasSeparator { fraction.append(character) } else { whole.append(character) }
            } else if index == lastMark, fractionDigits > 0 {
                hasSeparator = true
            }
        }
        // "007" → "7", but keep a single "0" before the separator ("0,5").
        while whole.count > 1, whole.hasPrefix("0") { whole.removeFirst() }
        if hasSeparator && whole.isEmpty { whole = "0" }
        let grouped = group(whole, locale: locale)
        guard hasSeparator else { return grouped }
        return grouped + separator + String(fraction.prefix(fractionDigits))
    }

    /// The number typed, or nil while the field is empty.
    static func value(of text: String, locale: Locale = .current) -> Double? {
        let separator = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        let normalised = text
            .filter { !grouping.contains($0) && !$0.isWhitespace }
            .replacingOccurrences(of: separator, with: ".")
        guard !normalised.isEmpty else { return nil }
        return Double(normalised)
    }

    /// How a stored amount appears in the field: grouped, no trailing zeros, and
    /// empty for zero so the placeholder shows.
    static func text(for value: Double, fractionDigits: Int, locale: Locale = .current) -> String {
        guard value.isFinite, value != 0 else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...fractionDigits)).locale(locale))
    }

    /// Whole-number digits with the locale's grouping, via `Decimal` so a long
    /// amount never overflows.
    private static func group(_ digits: String, locale: Locale) -> String {
        guard digits.count > 3, let number = Decimal(string: digits) else { return digits }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: number as NSDecimalNumber) ?? digits
    }
}
