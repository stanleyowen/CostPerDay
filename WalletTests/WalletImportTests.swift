import Testing
import Foundation
@testable import Wallet

/// The Wallet importer, against synthetic exports shaped exactly like real ones
/// (`;`-delimited, quoted multi-line notes, two-legged transfers, `envelope_id`s).
@Suite("Wallet import")
struct WalletImportTests {
    static let header = "account;category;currency;amount;ref_currency_amount;type;payment_type;payment_type_local;note;date;gps_latitude;gps_longitude;gps_accuracy_in_meters;warranty_in_month;transfer;payee;labels;envelope_id;custom_category"

    static func row(_ account: String, _ category: String, _ currency: String, _ amount: String, _ ref: String,
                    _ type: String, note: String = "", date: String, transfer: Bool = false, labels: String = "", envelope: String) -> String {
        "\(account);\(category);\(currency);\(amount);\(ref);\(type);CASH;Cash;\(note);\(date);;;;0;\(transfer);;\(labels);\(envelope);false"
    }

    static let utc = TimeZone(identifier: "UTC")!

    @Test("Parses ordinary expenses and income with categories, labels and notes")
    func ordinaryRecords() throws {
        let csv = [
            Self.header,
            Self.row("Bank (TWD)", "Food & Drinks", "TWD", "-92.00", "-92.00", "Expenses", note: "便當", date: "2026-01-15 12:30:00", labels: "Family Mart|Friends", envelope: "1003"),
            Self.row("Checking (TWD)", "Income", "TWD", "12000.00", "12000.00", "Income", note: "Salary", date: "2026-01-14 09:00:00", envelope: "10011"),
        ].joined(separator: "\n")
        let plan = try WalletImport.plan(fromText: csv, timeZone: Self.utc)

        #expect(plan.records.count == 2)
        #expect(plan.expenseCount == 1)
        #expect(plan.incomeCount == 1)
        let expense = try #require(plan.records.first { $0.kind == .expense })
        #expect(expense.amount == 92)
        #expect(expense.category == .foodGeneral)
        #expect(expense.labels == ["Family Mart", "Friends"])
        #expect(expense.note == "便當")
        #expect(expense.account == "Bank (TWD)")
        let income = try #require(plan.records.first { $0.kind == .income })
        #expect(income.category == .incomeGeneral)
        #expect(plan.referenceCurrency == "TWD")
        #expect(Set(plan.accounts.map(\.name)) == ["Bank (TWD)", "Checking (TWD)"])
    }

    @Test("Quoted notes keep embedded semicolons, quotes and newlines")
    func quotedMultilineNotes() throws {
        let csv = Self.header + "\n" +
            "Cash;Groceries;TWD;-100.00;-100.00;Expenses;CASH;Cash;\"Milk; eggs\nand \"\"bread\"\"\";2025-01-02 10:00:00;;;;0;false;;;1000;false\n"
        let plan = try WalletImport.plan(fromText: csv, timeZone: Self.utc)
        let record = try #require(plan.records.first)
        #expect(record.note == "Milk; eggs\nand \"bread\"")
        #expect(record.category == .groceries)
    }

    @Test("Two transfer legs at the same instant become one transfer")
    func pairsTransfers() throws {
        let csv = [
            Self.header,
            Self.row("Bank (TWD)", "TRANSFER", "TWD", "18.00", "18.00", "Income", date: "2026-01-12 18:00:00", transfer: true, envelope: "20001"),
            Self.row("E-wallet", "TRANSFER", "TWD", "-18.00", "-18.00", "Expenses", date: "2026-01-12 18:00:00", transfer: true, envelope: "20001"),
        ].joined(separator: "\n")
        let plan = try WalletImport.plan(fromText: csv, timeZone: Self.utc)
        #expect(plan.records.count == 1)
        #expect(plan.pairedTransfers == 1)
        let transfer = try #require(plan.records.first)
        #expect(transfer.kind == .transfer)
        #expect(transfer.account == "E-wallet")
        #expect(transfer.toAccount == "Bank (TWD)")
        #expect(transfer.amount == 18)
    }

    @Test("A cross-currency transfer keeps both amounts, even when they don't match")
    func crossCurrencyTransfer() throws {
        let csv = [
            Self.header,
            Self.row("Checking (USD)", "TRANSFER", "USD", "1.00", "32.50", "Income", date: "2026-01-10 10:00:00", transfer: true, envelope: "20001"),
            Self.row("Checking (TWD)", "TRANSFER", "TWD", "-33.00", "-33.00", "Expenses", date: "2026-01-10 10:00:00", transfer: true, envelope: "20001"),
        ].joined(separator: "\n")
        let plan = try WalletImport.plan(fromText: csv, timeZone: Self.utc)
        let transfer = try #require(plan.records.first)
        #expect(plan.records.count == 1)
        #expect(transfer.account == "Checking (TWD)")
        #expect(transfer.toAccount == "Checking (USD)")
        #expect(transfer.amount == 33)
        #expect(transfer.currency == "TWD")
        #expect(transfer.toAmount == 1)
    }

    @Test("A transfer leg with no partner is kept as money moving in or out of Wallet")
    func externalTransfers() throws {
        let csv = [
            Self.header,
            Self.row("Cash (NTD)", "TRANSFER", "TWD", "-300.00", "-300.00", "Expenses", note: "Card top-up", date: "2025-02-06 21:00:00", transfer: true, envelope: "20001"),
            Self.row("Bank (TWD)", "TRANSFER", "TWD", "5000.00", "5000.00", "Income", date: "2026-06-15 12:00:00", transfer: true, envelope: "20001"),
        ].joined(separator: "\n")
        let plan = try WalletImport.plan(fromText: csv, timeZone: Self.utc)
        #expect(plan.externalTransfers == 2)
        #expect(plan.pairedTransfers == 0)
        let out = try #require(plan.records.first { $0.account == "Cash (NTD)" })
        #expect(out.kind == .transfer && out.toAccount == nil)
        let into = try #require(plan.records.first { $0.toAccount == "Bank (TWD)" })
        #expect(into.kind == .transfer && into.account == nil)
    }

    @Test("Foreign-currency records carry Wallet's rate to the reference currency")
    func referenceRates() throws {
        let csv = [
            Self.header,
            Self.row("Cash (MYR)", "Food & Drinks", "MYR", "-20.00", "-146.00", "Expenses", date: "2025-05-01 12:00:00", envelope: "1003"),
            Self.row("Bank (TWD)", "Food & Drinks", "TWD", "-50.00", "-50.00", "Expenses", date: "2025-05-02 12:00:00", envelope: "1003"),
            Self.row("Bank (TWD)", "Food & Drinks", "TWD", "-60.00", "-60.00", "Expenses", date: "2025-05-03 12:00:00", envelope: "1003"),
        ].joined(separator: "\n")
        let plan = try WalletImport.plan(fromText: csv, timeZone: Self.utc)
        #expect(plan.referenceCurrency == "TWD")
        let myr = try #require(plan.records.first { $0.currency == "MYR" })
        #expect(abs(myr.refRate - 146.0 / 20.0) < 0.0001)
        #expect(plan.accounts.first { $0.name == "Cash (MYR)" }?.currency == "MYR")
        #expect(plan.accounts.first { $0.name == "Cash (MYR)" }?.kind == .cash)
    }

    @Test("Categories map by envelope ID first, then by English name; lottery flips by direction")
    func categoryMapping() {
        #expect(WalletImport.category(envelopeID: 6009, name: "anything", isIncome: false) == .travel)
        #expect(WalletImport.category(envelopeID: nil, name: "Pets, animals", isIncome: false) == .pets)
        #expect(WalletImport.category(envelopeID: 99_999, name: "Mystery", isIncome: false) == .unknown)
        #expect(WalletImport.category(envelopeID: 99_999, name: "Mystery", isIncome: true) == .incomeGeneral)
        #expect(WalletImport.category(envelopeID: 6012, name: "Lottery, gambling", isIncome: true) == .lotteryWinnings)
        #expect(WalletImport.category(envelopeID: 10007, name: "Lottery, gambling", isIncome: false) == .lottery)
    }

    @Test("Import keys are stable across re-exports and distinct for identical twins")
    func stableKeys() throws {
        let line = Self.row("Cash", "Food & Drinks", "TWD", "-50.00", "-50.00", "Expenses", note: "Lunch", date: "2025-03-01 12:00:00", envelope: "1003")
        let first = try WalletImport.plan(fromText: Self.header + "\n" + line, timeZone: Self.utc)
        let again = try WalletImport.plan(fromText: Self.header + "\n" + line, timeZone: Self.utc)
        #expect(first.records[0].key == again.records[0].key)

        let twins = try WalletImport.plan(fromText: [Self.header, line, line].joined(separator: "\n"), timeZone: Self.utc)
        #expect(twins.records.count == 2)
        #expect(Set(twins.records.map(\.key)).count == 2)
    }

    @Test("Rejects files that aren't Wallet exports, and skips unreadable rows")
    func rejectsGarbage() throws {
        #expect(throws: WalletImport.Failure.self) {
            try WalletImport.plan(fromText: "name,price\nfoo,1\n")
        }
        let csv = [
            Self.header,
            Self.row("Cash", "Food & Drinks", "TWD", "abc", "abc", "Expenses", date: "2025-03-01 12:00:00", envelope: "1003"),
            Self.row("Cash", "Food & Drinks", "TWD", "-10", "-10", "Expenses", date: "not a date", envelope: "1003"),
            Self.row("Cash", "Food & Drinks", "TWD", "-10", "-10", "Expenses", date: "2025-03-01 12:00:00", envelope: "1003"),
        ].joined(separator: "\n")
        let plan = try WalletImport.plan(fromText: csv, timeZone: Self.utc)
        #expect(plan.records.count == 1)
        #expect(plan.skippedRows == 2)
    }

    @Test("Imports into SwiftData, matching accounts by name, and re-importing adds nothing")
    @MainActor
    func importIsIdempotent() async throws {
        let container = try DataStore.inMemoryContainer()
        let existing = Account(name: "Bank (TWD)", kind: .bank, currencyCode: "TWD")
        container.mainContext.insert(existing)
        try container.mainContext.save()

        let csv = [
            Self.header,
            Self.row("Bank (TWD)", "Food & Drinks", "TWD", "-92.00", "-92.00", "Expenses", date: "2026-01-15 12:30:00", envelope: "1003"),
            Self.row("Bank (TWD)", "TRANSFER", "TWD", "18.00", "18.00", "Income", date: "2026-01-12 18:00:00", transfer: true, envelope: "20001"),
            Self.row("E-wallet", "TRANSFER", "TWD", "-18.00", "-18.00", "Expenses", date: "2026-01-12 18:00:00", transfer: true, envelope: "20001"),
        ].joined(separator: "\n")
        let plan = try WalletImport.plan(fromText: csv, timeZone: Self.utc)
        let writer = LedgerWriter(modelContainer: container)

        let first = try await writer.importWallet(plan, factor: 1, baseCurrency: "TWD")
        #expect(first.added == 2)
        #expect(first.accountsCreated == 1) // E-wallet only; Bank (TWD) already existed

        let second = try await writer.importWallet(plan, factor: 1, baseCurrency: "TWD")
        #expect(second.added == 0)
        #expect(second.skipped == 2)
    }
}

@Suite("CSV")
struct CSVTests {
    @Test("Lenient number parsing across export styles")
    func numbers() {
        #expect(CSV.number("-92.00") == -92)
        #expect(CSV.number("1,234.50") == 1234.5)
        #expect(CSV.number("1.234,50") == 1234.5)
        #expect(CSV.number("1 234,50") == 1234.5)
        #expect(CSV.number("12,5") == 12.5)
        #expect(CSV.number("1,234") == 1234)
        #expect(CSV.number("0,500") == 0.5)
        #expect(CSV.number("") == nil)
        #expect(CSV.number("abc") == nil)
    }

    @Test("Detects the delimiter from the header")
    func delimiter() {
        #expect(CSV.detectDelimiter(in: "a;b;c\n1;2;3") == ";")
        #expect(CSV.detectDelimiter(in: "a,b,c\n1,2,3") == ",")
        #expect(CSV.detectDelimiter(in: "a\tb\tc") == "\t")
    }

    @Test("Handles CRLF, BOM and a trailing newline")
    func lineEndings() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("a,b\r\n1,2\r\n".utf8)
        let rows = CSV.parse(try CSV.decodeText(data))
        #expect(rows == [["a", "b"], ["1", "2"]])
    }

    @Test("Exported text can't run as a spreadsheet formula")
    func formulaInjection() {
        #expect(CSV.escape("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(CSV.escape("@SUM(A1)") == "'@SUM(A1)")
        #expect(CSV.escape("-92") == "-92") // a real negative number stays a number
        #expect(CSV.escape("a,b") == "\"a,b\"")
    }
}
