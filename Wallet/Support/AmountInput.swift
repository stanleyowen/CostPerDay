import Foundation

/// The amount field in the transaction editor: plain text typed on the system
/// decimal keyboard, kept to a well-formed number in the user's own notation.
enum AmountInput {
    /// Digits and one decimal separator (the locale's), with no more decimals than
    /// the currency has. A pasted "." or "," counts as the separator; when both
    /// appear, the last one is the decimal point and the others are dropped as
    /// grouping ("1,234.50" → "1234.50").
    static func sanitize(_ text: String, fractionDigits: Int, locale: Locale = .current) -> String {
        let separator = locale.decimalSeparator ?? "."
        let marks: Set<Character> = [".", ",", Character(separator)]
        let lastMark = text.lastIndex { marks.contains($0) }
        var whole = "", fraction = "", hasSeparator = false
        for index in text.indices {
            let character = text[index]
            if character.isASCII, character.isNumber {
                if hasSeparator { fraction.append(character) } else { whole.append(character) }
            } else if index == lastMark, fractionDigits > 0 {
                hasSeparator = true
            }
        }
        // "007" → "7", but keep a single "0" before the separator ("0,5").
        while whole.count > 1, whole.hasPrefix("0") { whole.removeFirst() }
        if hasSeparator && whole.isEmpty { whole = "0" }
        guard hasSeparator else { return whole }
        return whole + separator + String(fraction.prefix(fractionDigits))
    }

    /// The number typed, or nil while the field is empty.
    static func value(of text: String, locale: Locale = .current) -> Double? {
        let separator = locale.decimalSeparator ?? "."
        let normalised = text.replacingOccurrences(of: separator, with: ".")
        guard !normalised.isEmpty else { return nil }
        return Double(normalised)
    }

    /// How a stored amount appears in the field: no grouping, no trailing zeros,
    /// and empty for zero so the placeholder shows.
    static func text(for value: Double, fractionDigits: Int, locale: Locale = .current) -> String {
        guard value.isFinite, value != 0 else { return "" }
        return value.formatted(.number.grouping(.never).precision(.fractionLength(0...fractionDigits)).locale(locale))
    }
}
