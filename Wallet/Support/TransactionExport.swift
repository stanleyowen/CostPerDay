import Foundation

/// Plain CSV of transactions, for spreadsheets or moving elsewhere. Text cells are
/// escaped against formula injection (see `CSV.escape`).
enum TransactionExport {
    static let header = ["date", "type", "account", "to_account", "category", "group", "amount", "currency",
                         "received_amount", "amount_in_base", "base_currency", "note", "payee", "labels", "tracked_item"]

    static func csv(records: [Record], accounts: [Account], baseCurrency: String) -> String {
        let names = Dictionary(accounts.map { ($0.uuid, $0.name) }, uniquingKeysWith: { first, _ in first })
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        func number(_ value: Double) -> String {
            String(format: "%.4f", value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        }
        var lines = [CSV.line(header)]
        for record in records.sorted(by: { $0.date < $1.date }) {
            let flow = record.flow
            let signed: Double = switch flow.kind {
            case .expense: -flow.safeAmount
            case .income: flow.safeAmount
            case .transfer: -flow.safeAmount
            }
            lines.append(CSV.line([
                formatter.string(from: flow.date),
                flow.kind.rawValue,
                flow.accountID.flatMap { names[$0] } ?? "",
                flow.toAccountID.flatMap { names[$0] } ?? "",
                flow.kind == .transfer ? "" : flow.category.label,
                flow.kind == .transfer ? "" : flow.category.group.label,
                number(signed),
                flow.currencyCode,
                flow.toAmount > 0 ? number(flow.toAmount) : "",
                number(flow.kind == .income ? flow.baseAmount : -flow.baseAmount),
                baseCurrency,
                flow.note,
                flow.payee,
                flow.labels.joined(separator: "|"),
                record.item?.name ?? "",
            ]))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func writeCSV(records: [Record], accounts: [Account], baseCurrency: String, title: String) throws -> URL {
        let safeTitle = title.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Wallet-\(safeTitle.isEmpty ? "transactions" : safeTitle).csv")
        // BOM so Excel opens non-Latin notes correctly.
        let data = Data([0xEF, 0xBB, 0xBF]) + Data(csv(records: records, accounts: accounts, baseCurrency: baseCurrency).utf8)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}
