import SwiftUI
import SwiftData

/// Everything a screen needs about accounts and balances, derived once per render
/// from the raw queries (same rule as `ItemListView.Snapshot`: never as computed
/// properties read over and over).
struct LedgerSnapshot {
    let accounts: [Account]
    let refs: [AccountRef]
    let flows: [Flow]
    let balances: [UUID: Double]
    let rates: [String: Double]
    let netWorth: Double
    let excludedFromStats: Set<UUID>
    private let byID: [UUID: Account]

    init(accounts: [Account], records: [Record], baseCurrency: String) {
        let sorted = accounts.sorted { ($0.isArchived ? 1 : 0, $0.sortOrder, $0.createdAt) < ($1.isArchived ? 1 : 0, $1.sortOrder, $1.createdAt) }
        self.accounts = sorted
        refs = sorted.map(AccountRef.init)
        flows = records.map(\.flow)
        balances = Ledger.balances(accounts: refs, flows: flows)
        rates = Ledger.latestRates(flows: flows, baseCurrency: baseCurrency)
        netWorth = Ledger.netWorth(accounts: refs, balances: balances, rates: rates)
        excludedFromStats = Set(sorted.filter(\.excludeFromStats).map(\.uuid))
        byID = Dictionary(sorted.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func account(_ id: UUID?) -> Account? { id.flatMap { byID[$0] } }

    func balance(of account: Account) -> Double { balances[account.uuid] ?? account.initialBalance }

    func balanceInBase(of account: Account) -> Double {
        Ledger.toBase(balance(of: account), currency: account.currencyCode, rates: rates)
    }

    var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }

    /// "Bank → Cash", "Outside → Transit card", or just the account name.
    func accountLine(for flow: Flow) -> String {
        let outside = String(localized: "Outside", comment: "Placeholder for money moving to or from an untracked account")
        switch flow.kind {
        case .transfer:
            let from = account(flow.accountID)?.displayName ?? outside
            let to = account(flow.toAccountID)?.displayName ?? outside
            return "\(from) → \(to)"
        case .expense, .income:
            return account(flow.accountID)?.displayName ?? String(localized: "Deleted account", comment: "Shown for a transaction whose account was removed")
        }
    }
}

// MARK: - Money formatting for transactions

extension Money {
    /// A ledger amount: exact, but without meaningless ".00" on whole amounts —
    /// "NT$92", "$12.50", "¥1,200".
    static func exact(_ value: Double, code: String) -> String {
        guard value.isFinite else { return "—" }
        let digits = Currency.fractionDigits(code)
        let rounded = (value * pow(10, Double(digits))).rounded() / pow(10, Double(digits))
        let whole = rounded == rounded.rounded()
        return rounded.formatted(.currency(code: code).precision(.fractionLength(whole ? 0 : digits)))
    }

    /// Short axis labels: "NT$12K".
    static func compact(_ value: Double, code: String) -> String {
        guard value.isFinite else { return "—" }
        if abs(value) < 1000 { return string(value, code: code) }
        return value.formatted(.currency(code: code).notation(.compactName).precision(.significantDigits(1...3)))
    }

    /// A signed ledger amount: "−NT$92", "+NT$12,000".
    static func signed(_ value: Double, code: String, kind: RecordKind) -> String {
        let text = exact(abs(value), code: code)
        switch kind {
        case .expense: return "−" + text
        case .income: return "+" + text
        case .transfer: return text
        }
    }
}

extension Color {
    static let income = Color(red: 0.13, green: 0.66, blue: 0.36)
    static let expense = Brand.expense
}
