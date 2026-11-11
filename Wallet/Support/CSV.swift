import Foundation

/// A small RFC 4180 CSV reader/writer: quoted fields, doubled quotes, embedded
/// delimiters and newlines, CRLF or LF, optional UTF-8 BOM. Imports are untrusted
/// input, so it never evaluates anything and caps how much it will read.
enum CSV {
    static let maxBytes = 50 * 1024 * 1024

    enum Failure: LocalizedError {
        case tooLarge, notText, empty

        var errorDescription: String? {
            switch self {
            case .tooLarge:
                String(localized: "The file is too large to import.", comment: "CSV import error")
            case .notText:
                String(localized: "The file is not readable text. Please export it as CSV (UTF-8).", comment: "CSV import error")
            case .empty:
                String(localized: "The file contains no transactions.", comment: "CSV import error")
            }
        }
    }

    static func decodeText(_ data: Data) throws -> String {
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        if let text = String(data: bytes, encoding: .utf8) { return text }
        if let text = String(data: bytes, encoding: .utf16) { return text }
        throw Failure.notText
    }

    /// Picks `;`, `,` or tab by whichever splits the header line into the most fields.
    static func detectDelimiter(in text: String) -> Character {
        let header = text.prefix { $0 != "\n" && $0 != "\r" }
        let candidates: [Character] = [";", ",", "\t"]
        return candidates.max { a, b in header.filter { $0 == a }.count < header.filter { $0 == b }.count } ?? ","
    }

    static func parse(_ text: String, delimiter: Character? = nil) -> [[String]] {
        let delimiter = delimiter ?? detectDelimiter(in: text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let char = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"" where field.isEmpty:
                inQuotes = true
            case delimiter:
                endField()
            case "\n", "\r\n":
                endRow()
            case "\r":
                // A lone CR (old Mac line ending); CRLF arrives as one grapheme above.
                endRow()
            default:
                field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    // MARK: Writing

    static func escape(_ value: String, delimiter: Character = ",") -> String {
        var value = value
        // Spreadsheet apps execute cells that start with these as formulas; a
        // transaction note shouldn't be able to do that to whoever opens the export.
        if let first = value.first, "=+-@\t\r".contains(first), Double(value) == nil {
            value = "'" + value
        }
        if value.contains(delimiter) || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static func line(_ fields: [String], delimiter: Character = ",") -> String {
        fields.map { escape($0, delimiter: delimiter) }.joined(separator: String(delimiter))
    }

    /// Lenient number parsing for exported amounts: "1234.50", "-92.00", "1,234.50",
    /// "1 234,50", "1.234,50".
    static func number(_ raw: String) -> Double? {
        var text = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard !text.isEmpty else { return nil }
        let lastComma = text.lastIndex(of: ",")
        let lastDot = text.lastIndex(of: ".")
        switch (lastComma, lastDot) {
        case let (comma?, dot?):
            if comma > dot {
                text = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                text = text.replacingOccurrences(of: ",", with: "")
            }
        case (_?, nil):
            // A lone comma followed by exactly three digits is a thousands separator.
            let parts = text.split(separator: ",")
            let leading = parts.first.map(String.init) ?? ""
            if parts.count > 1, leading != "0", leading != "-0", parts.dropFirst().allSatisfy({ $0.count == 3 }) {
                text = text.replacingOccurrences(of: ",", with: "")
            } else {
                text = text.replacingOccurrences(of: ",", with: ".")
            }
        default:
            break
        }
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }
}
