import Foundation
import CryptoKit

/// Reads a BudgetBakers Wallet "records" CSV export and turns it into a plan Wallet
/// can show before anything is written. Pure and Sendable — the actual inserts
/// happen in `LedgerWriter`.
///
/// Wallet quirks this handles:
/// * `;`-delimited, quoted multi-line notes.
/// * Transfers are exported as two legs sharing a timestamp (one negative, one
///   positive). They're re-paired into a single transfer; a leg with no partner was
///   a transfer to or from somewhere outside Wallet and is kept as such.
/// * `ref_currency_amount` is the amount in Wallet's reference currency, which gives
///   the exchange rate at the time of each record.
/// * `envelope_id` identifies the category independently of the display language.
enum WalletImport {
    struct Leg: Sendable, Hashable {
        var account: String
        var categoryName: String
        var envelopeID: Int?
        var currency: String
        var amount: Double
        var refAmount: Double
        var isIncome: Bool
        var note: String
        var payee: String
        var labels: [String]
        var date: Date
        var dateText: String
        var isTransfer: Bool
    }

    struct PlannedRecord: Sendable, Hashable {
        var key: String
        var kind: RecordKind
        var amount: Double
        var currency: String
        /// Per unit of `currency`, in the export's reference currency.
        var refRate: Double
        var date: Date
        var account: String?
        var toAccount: String?
        var toAmount: Double
        var category: RecordCategory
        var note: String
        var payee: String
        var labels: [String]
    }

    struct PlannedAccount: Sendable, Hashable, Identifiable {
        var name: String
        var currency: String
        var recordCount: Int
        var kind: AccountKind
        var id: String { name }
    }

    struct Plan: Sendable {
        var records: [PlannedRecord]
        var accounts: [PlannedAccount]
        /// The currency Wallet reported `ref_currency_amount` in.
        var referenceCurrency: String
        var firstDate: Date?
        var lastDate: Date?
        var pairedTransfers: Int
        var externalTransfers: Int
        var skippedRows: Int
        var expenseCount: Int { records.filter { $0.kind == .expense }.count }
        var incomeCount: Int { records.filter { $0.kind == .income }.count }
        var transferCount: Int { records.filter { $0.kind == .transfer }.count }
        var labelCount: Int { Set(records.flatMap(\.labels)).count }
    }

    enum Failure: LocalizedError {
        case missingColumns([String])

        var errorDescription: String? {
            switch self {
            case .missingColumns(let names):
                String(localized: "This doesn't look like a BudgetBakers export. Missing columns: \(names.joined(separator: ", ")).", comment: "Import error. The placeholder is a list of column names.")
            }
        }
    }

    // MARK: Parsing

    static func plan(from data: Data, timeZone: TimeZone = .current) throws -> Plan {
        try plan(fromText: CSV.decodeText(data), timeZone: timeZone)
    }

    static func plan(fromText text: String, timeZone: TimeZone = .current) throws -> Plan {
        let rows = CSV.parse(text)
        guard let header = rows.first else { throw CSV.Failure.empty }
        let columns = Dictionary(
            header.enumerated().map { ($0.element.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        let required = ["account", "category", "currency", "amount", "date"]
        let missing = required.filter { columns[$0] == nil }
        guard missing.isEmpty else { throw Failure.missingColumns(missing) }

        func value(_ row: [String], _ name: String) -> String {
            guard let index = columns[name], index < row.count else { return "" }
            return row[index]
        }

        let parseDate = dateParser(timeZone: timeZone)
        var legs: [Leg] = []
        var skipped = 0
        for row in rows.dropFirst() {
            let amountText = value(row, "amount")
            guard let amount = CSV.number(amountText), amount != 0,
                  let date = parseDate(value(row, "date").trimmingCharacters(in: .whitespaces)) else {
                skipped += 1
                continue
            }
            let account = value(row, "account").trimmingCharacters(in: .whitespacesAndNewlines)
            let currency = value(row, "currency").trimmingCharacters(in: .whitespaces).uppercased()
            guard !account.isEmpty, currency.count == 3 else { skipped += 1; continue }
            let ref = CSV.number(value(row, "ref_currency_amount")) ?? amount
            let type = value(row, "type").lowercased()
            let transferFlag = value(row, "transfer").lowercased()
            legs.append(Leg(
                account: account,
                categoryName: value(row, "category").trimmingCharacters(in: .whitespaces),
                envelopeID: Int(value(row, "envelope_id").trimmingCharacters(in: .whitespaces)),
                currency: currency,
                amount: amount,
                refAmount: ref,
                isIncome: type.isEmpty ? amount > 0 : type.hasPrefix("income"),
                note: value(row, "note").trimmingCharacters(in: .whitespacesAndNewlines),
                payee: value(row, "payee").trimmingCharacters(in: .whitespacesAndNewlines),
                labels: value(row, "labels").split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                date: date,
                dateText: value(row, "date").trimmingCharacters(in: .whitespaces),
                isTransfer: transferFlag == "true" || transferFlag == "1"
            ))
        }
        guard !legs.isEmpty else { throw CSV.Failure.empty }
        return build(legs: legs, skipped: skipped)
    }

    static func build(legs: [Leg], skipped: Int = 0) -> Plan {
        var records: [PlannedRecord] = []
        var occurrences: [String: Int] = [:]

        func uniqueKey(_ base: String) -> String {
            let n = occurrences[base, default: 0]
            occurrences[base] = n + 1
            return n == 0 ? base : "\(base)#\(n)"
        }

        func refRate(_ leg: Leg) -> Double {
            let rate = abs(leg.refAmount) / abs(leg.amount)
            return rate.isFinite && rate > 0 ? rate : 1
        }

        // Ordinary income and expense.
        for leg in legs where !leg.isTransfer {
            records.append(PlannedRecord(
                key: uniqueKey(legKey(leg)),
                kind: leg.amount > 0 ? .income : .expense,
                amount: abs(leg.amount),
                currency: leg.currency,
                refRate: refRate(leg),
                date: leg.date,
                account: leg.account,
                toAccount: nil,
                toAmount: 0,
                category: category(envelopeID: leg.envelopeID, name: leg.categoryName, isIncome: leg.amount > 0),
                note: leg.note,
                payee: leg.payee,
                labels: leg.labels
            ))
        }

        // Transfers: re-pair the two legs written at the same instant.
        var paired = 0, external = 0
        let groups = Dictionary(grouping: legs.filter(\.isTransfer), by: \.dateText)
        for (_, group) in groups.sorted(by: { $0.key < $1.key }) {
            var outgoing = group.filter { $0.amount < 0 }
            var incoming = group.filter { $0.amount > 0 }
            var matches: [(Leg, Leg)] = []

            if outgoing.count == 1, incoming.count == 1, outgoing[0].account != incoming[0].account {
                // The usual case. Amounts can legitimately differ (fees, currency).
                matches.append((outgoing[0], incoming[0]))
                outgoing.removeAll()
                incoming.removeAll()
            } else {
                for out in outgoing {
                    let candidates = incoming.enumerated().filter { $0.element.account != out.account }
                    guard let best = candidates.min(by: {
                        abs(abs($0.element.refAmount) - abs(out.refAmount)) < abs(abs($1.element.refAmount) - abs(out.refAmount))
                    }) else { continue }
                    matches.append((out, best.element))
                    incoming.remove(at: best.offset)
                }
                let matchedOut = Set(matches.map(\.0))
                outgoing.removeAll { matchedOut.contains($0) }
            }

            for (out, into) in matches {
                paired += 1
                records.append(PlannedRecord(
                    key: uniqueKey(legKey(out) + ">" + legKey(into)),
                    kind: .transfer,
                    amount: abs(out.amount),
                    currency: out.currency,
                    refRate: refRate(out),
                    date: out.date,
                    account: out.account,
                    toAccount: into.account,
                    toAmount: abs(into.amount),
                    category: .otherGeneral,
                    note: out.note.isEmpty ? into.note : out.note,
                    payee: out.payee.isEmpty ? into.payee : out.payee,
                    labels: RecordDraft.normalisedLabels(out.labels + into.labels)
                ))
            }
            for leg in outgoing + incoming {
                external += 1
                let isOut = leg.amount < 0
                records.append(PlannedRecord(
                    key: uniqueKey(legKey(leg)),
                    kind: .transfer,
                    amount: abs(leg.amount),
                    currency: leg.currency,
                    refRate: refRate(leg),
                    date: leg.date,
                    account: isOut ? leg.account : nil,
                    toAccount: isOut ? nil : leg.account,
                    toAmount: 0,
                    category: .otherGeneral,
                    note: leg.note,
                    payee: leg.payee,
                    labels: leg.labels
                ))
            }
        }

        records.sort { $0.date < $1.date }

        // Accounts, with the currency most of their records use.
        var currencyVotes: [String: [String: Int]] = [:]
        var counts: [String: Int] = [:]
        for leg in legs {
            currencyVotes[leg.account, default: [:]][leg.currency, default: 0] += 1
            counts[leg.account, default: 0] += 1
        }
        let accounts = counts.keys.sorted { counts[$0]! > counts[$1]! }.map { name in
            PlannedAccount(
                name: name,
                currency: currencyVotes[name]?.max { $0.value < $1.value }?.key ?? "USD",
                recordCount: counts[name] ?? 0,
                kind: AccountKind.guess(fromName: name)
            )
        }

        // The reference currency is the one whose amounts equal their reference amounts.
        var refVotes: [String: Int] = [:]
        for leg in legs where abs(leg.amount - leg.refAmount) < 0.0001 { refVotes[leg.currency, default: 0] += 1 }
        let reference = refVotes.max { $0.value < $1.value }?.key ?? legs.first?.currency ?? "USD"

        return Plan(
            records: records,
            accounts: accounts,
            referenceCurrency: reference,
            firstDate: records.first?.date,
            lastDate: records.last?.date,
            pairedTransfers: paired,
            externalTransfers: external,
            skippedRows: skipped
        )
    }

    /// Stable across re-exports of the same record, so importing a newer export only
    /// adds what's new. Hashed so notes don't leak into an index-sized key.
    static func legKey(_ leg: Leg) -> String {
        let raw = [leg.account, leg.dateText, String(format: "%.4f", leg.amount), leg.currency, leg.note, leg.categoryName]
            .joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return "wallet:" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static func dateParser(timeZone: TimeZone) -> (String) -> Date? {
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"]
        let formatters = formats.map { format -> DateFormatter in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            return formatter
        }
        return { text in
            for formatter in formatters {
                if let date = formatter.date(from: text) { return date }
            }
            return nil
        }
    }

    // MARK: Categories

    /// Wallet's stable category identifiers, as seen in real exports.
    static let envelopeMap: [Int: RecordCategory] = [
        1000: .groceries, 1001: .restaurant, 1002: .barCafe, 1003: .foodGeneral,
        2000: .clothes, 2001: .jewels, 2002: .healthBeauty, 2003: .kids, 2004: .homeGarden,
        2005: .pets, 2006: .electronics, 2007: .gifts, 2008: .stationery, 2009: .freeTime,
        2010: .shoppingGeneral, 2011: .drugstore,
        3000: .rent, 3001: .mortgage, 3002: .utilities, 3003: .services, 3004: .maintenance,
        3005: .housingGeneral, 3006: .propertyInsurance,
        4000: .publicTransport, 4001: .taxi, 4002: .longDistance, 4003: .businessTrips, 4004: .transportGeneral,
        5000: .fuel, 5001: .parking, 5002: .vehicleMaintenance, 5003: .rentals, 5004: .vehicleInsurance, 5005: .leasing,
        6000: .healthCare, 6001: .wellness, 6002: .fitness, 6003: .events, 6004: .lifeEvents, 6005: .hobbies,
        6006: .education, 6007: .subscriptions, 6008: .streaming, 6009: .travel, 6010: .charity,
        6011: .alcoholTobacco, 6012: .lottery, 6013: .lifeGeneral,
        7001: .phone, 7002: .internet, 7003: .software, 7004: .postal,
        8001: .insurance, 8002: .loanInterest, 8003: .fines, 8005: .fees, 8008: .financialGeneral,
        10001: .interest, 10005: .lending, 10007: .lotteryWinnings, 10008: .refunds, 10011: .incomeGeneral,
        13001: .unknown,
    ]

    /// Wallet's English category names, as a fallback for IDs not in `envelopeMap`.
    static let nameMap: [String: RecordCategory] = [
        "food & drinks": .foodGeneral, "groceries": .groceries, "restaurant, fast-food": .restaurant,
        "bar, cafe": .barCafe, "shopping": .shoppingGeneral, "clothes & shoes": .clothes,
        "jewels, accessories": .jewels, "health and beauty": .healthBeauty, "kids": .kids,
        "home, garden": .homeGarden, "pets, animals": .pets, "electronics, accessories": .electronics,
        "gifts, joy": .gifts, "stationery, tools": .stationery, "free time": .freeTime,
        "drug-store, chemist": .drugstore, "housing": .housingGeneral, "rent": .rent,
        "mortgage": .mortgage, "energy, utilities": .utilities, "services": .services,
        "maintenance, repairs": .maintenance, "property insurance": .propertyInsurance,
        "transportation": .transportGeneral, "public transport": .publicTransport, "taxi": .taxi,
        "long distance": .longDistance, "business trips": .businessTrips, "vehicle": .vehicleGeneral,
        "fuel": .fuel, "parking": .parking, "vehicle maintenance": .vehicleMaintenance,
        "rentals": .rentals, "vehicle insurance": .vehicleInsurance, "leasing": .leasing,
        "life & entertainment": .lifeGeneral, "health care, doctor": .healthCare,
        "wellness, beauty": .wellness, "active sport, fitness": .fitness,
        "culture, sport events": .events, "life events": .lifeEvents, "hobbies": .hobbies,
        "education, development": .education, "books, audio, subscriptions": .subscriptions,
        "tv, streaming": .streaming, "holiday, trips, hotels": .travel, "charity, gifts": .charity,
        "alcohol, tobacco": .alcoholTobacco, "lottery, gambling": .lottery,
        "communication, pc": .communicationGeneral, "phone, cell phone": .phone, "internet": .internet,
        "software, apps, games": .software, "postal services": .postal,
        "financial expenses": .financialGeneral, "taxes": .taxes, "insurances": .insurance,
        "loan, interests": .loanInterest, "fines": .fines, "advisory": .advisory,
        "charges, fees": .fees, "child support": .childSupport, "investments": .investmentsGeneral,
        "realty": .realty, "vehicles, chattels": .vehiclesChattels,
        "financial investments": .financialInvestments, "savings": .savings, "collections": .collections,
        "income": .incomeGeneral, "wage, invoices": .wage, "interests, dividends": .interest,
        "sale": .sale, "rental income": .rentalIncome, "dues & grants": .grants,
        "lending, renting": .lending, "checks, coupons": .coupons, "gifts": .giftsReceived,
        "refunds (tax, purchase)": .refunds, "others": .otherGeneral, "missing": .unknown,
        "unknown expense": .unknown, "unknown income": .unknown,
    ]

    static func category(envelopeID: Int?, name: String, isIncome: Bool) -> RecordCategory {
        if let envelopeID, let mapped = envelopeMap[envelopeID] {
            return adjusted(mapped, isIncome: isIncome)
        }
        if let mapped = nameMap[name.lowercased()] {
            return adjusted(mapped, isIncome: isIncome)
        }
        return isIncome ? .incomeGeneral : .unknown
    }

    /// "Lottery, gambling" is both an expense and an income category in Wallet.
    private static func adjusted(_ category: RecordCategory, isIncome: Bool) -> RecordCategory {
        switch (category, isIncome) {
        case (.lottery, true): .lotteryWinnings
        case (.lotteryWinnings, false): .lottery
        default: category
        }
    }
}
