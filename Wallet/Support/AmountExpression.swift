import Foundation

/// The text behind the entry keypad: digits, one decimal point per number, and the
/// four operators. Evaluates with normal precedence (× ÷ before + −) so "120+45×2"
/// is what people expect. Never uses NSExpression or anything else that evaluates
/// arbitrary input.
struct AmountExpression: Equatable {
    private(set) var text: String = ""
    var maxFractionDigits: Int = 2

    static let operators: Set<Character> = ["+", "−", "×", "÷"]

    init(text: String = "", maxFractionDigits: Int = 2) {
        self.text = text
        self.maxFractionDigits = maxFractionDigits
    }

    init(value: Double, maxFractionDigits: Int = 2) {
        self.maxFractionDigits = maxFractionDigits
        if value > 0, value.isFinite {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = maxFractionDigits
            formatter.usesGroupingSeparator = false
            text = formatter.string(from: NSNumber(value: value)) ?? ""
        }
    }

    var isEmpty: Bool { text.isEmpty }
    var hasOperator: Bool { text.dropFirst().contains { Self.operators.contains($0) } }

    /// The number being typed right now — everything after the last operator.
    private var currentNumber: Substring {
        guard let op = text.lastIndex(where: { Self.operators.contains($0) }) else { return text[...] }
        return text[text.index(after: op)...]
    }

    mutating func input(_ key: Character) {
        switch key {
        case "0"..."9":
            let number = currentNumber
            if let dot = number.firstIndex(of: ".") {
                guard number.distance(from: dot, to: number.endIndex) - 1 < maxFractionDigits else { return }
            } else {
                guard number.count < 12 else { return }
                if number == "0" { text.removeLast() }
            }
            text.append(key)
        case ".":
            guard maxFractionDigits > 0, !currentNumber.contains(".") else { return }
            if currentNumber.isEmpty { text.append("0") }
            text.append(".")
        case _ where Self.operators.contains(key):
            guard !text.isEmpty else { return }
            if let last = text.last, Self.operators.contains(last) || last == "." { text.removeLast() }
            guard !text.isEmpty else { return }
            text.append(key)
        default:
            break
        }
    }

    mutating func backspace() {
        if !text.isEmpty { text.removeLast() }
    }

    mutating func clear() { text = "" }

    /// Replaces the expression with its result.
    mutating func collapse() {
        guard hasOperator, let value else { return }
        self = AmountExpression(value: value, maxFractionDigits: maxFractionDigits)
    }

    /// The result, or nil if it's empty, ends mid-operation into nothing, or divides by zero.
    var value: Double? {
        var tokens: [String] = []
        var number = ""
        for char in text {
            if Self.operators.contains(char) {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(char))
            } else {
                number.append(char)
            }
        }
        if !number.isEmpty { tokens.append(number) }
        // A trailing operator is just "not finished typing" — ignore it.
        if let last = tokens.last, last.count == 1, Self.operators.contains(Character(last)) { tokens.removeLast() }
        guard !tokens.isEmpty else { return nil }

        // First pass: × and ÷.
        var terms: [Double] = []
        var ops: [Character] = []
        var index = 0
        guard var current = Double(tokens[0]) else { return nil }
        index = 1
        while index + 1 < tokens.count {
            let op = Character(tokens[index])
            guard let rhs = Double(tokens[index + 1]) else { return nil }
            switch op {
            case "×": current *= rhs
            case "÷":
                guard rhs != 0 else { return nil }
                current /= rhs
            default:
                terms.append(current)
                ops.append(op)
                current = rhs
            }
            index += 2
        }
        terms.append(current)

        // Second pass: + and −.
        var result = terms[0]
        for (op, term) in zip(ops, terms.dropFirst()) {
            result = op == "+" ? result + term : result - term
        }
        guard result.isFinite else { return nil }
        let scale = pow(10, Double(maxFractionDigits))
        return (result * scale).rounded() / scale
    }
}
