import Foundation
import SwiftData

enum RecordKind: String, CaseIterable, Identifiable, Codable {
    case expense, income, transfer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .expense: String(localized: "Expense", comment: "Transaction type")
        case .income: String(localized: "Income", comment: "Transaction type")
        case .transfer: String(localized: "Transfer", comment: "Transaction type")
        }
    }

    var symbol: String {
        switch self {
        case .expense: "arrow.up.right"
        case .income: "arrow.down.left"
        case .transfer: "arrow.left.arrow.right"
        }
    }
}

/// One transaction: money out, money in, or money moved between accounts.
///
/// Named `Record` (as BudgetBakers Wallet calls them) because `Transaction` is
/// already a SwiftUI type. Amounts are stored as positive magnitudes; `kind`
/// carries the direction.
@Model
final class Record {
    #Index<Record>([\.date], [\.accountID], [\.toAccountID])

    var uuid: UUID = UUID()
    var kindRaw: String = RecordKind.expense.rawValue
    /// Always ≥ 0, in `currencyCode`. For a transfer, the amount leaving the source.
    var amount: Double = 0
    /// The source account's currency at the time the record was made.
    var currencyCode: String = "USD"
    /// Locked when recorded, like an item's purchase rate: one unit of `currencyCode`
    /// is worth this many base-currency units. Rescaled wholesale on a base change.
    var rateToBase: Double = 1
    var date: Date = Date()
    /// The account the money left (expense, transfer) or arrived in (income).
    /// Nil only for a transfer that came in from outside the tracked accounts.
    var accountID: UUID?
    /// Transfers only: where the money went. Nil for a transfer out of the tracked accounts.
    var toAccountID: UUID?
    /// Transfers only: what arrived, in the destination account's currency. Zero
    /// means "same as `amount`" (a same-currency transfer).
    var toAmount: Double = 0
    /// A `RecordCategory` raw value. Resolve with `RecordCategoryDisplay.resolve`.
    var categoryRaw: String = RecordCategory.otherGeneral.rawValue
    var note: String = ""
    var payee: String = ""
    var labels: [String] = []
    /// Set on records brought in from another app, so re-importing a newer export
    /// only adds what's new.
    var importKey: String?
    /// The user said "no thanks" to tracking this purchase as an item.
    var lifecycleDismissed: Bool = false
    var createdAt: Date = Date()

    /// The owned item this money went into: its purchase, or upkeep on it.
    var item: Gadget?
    /// True when this record *is* the linked item's purchase (its price is already
    /// counted in the item), false when it's upkeep on top.
    var isItemPurchase: Bool = false

    init(
        kind: RecordKind = .expense,
        amount: Double = 0,
        currencyCode: String = Currency.deviceDefault,
        rateToBase: Double = 1,
        date: Date = .now,
        accountID: UUID? = nil,
        toAccountID: UUID? = nil,
        toAmount: Double = 0,
        category: RecordCategory = .otherGeneral,
        note: String = "",
        payee: String = "",
        labels: [String] = []
    ) {
        self.uuid = UUID()
        self.kindRaw = kind.rawValue
        self.amount = amount
        self.currencyCode = currencyCode
        self.rateToBase = rateToBase
        self.date = date
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.toAmount = toAmount
        self.categoryRaw = category.rawValue
        self.note = note
        self.payee = payee
        self.labels = labels
        self.createdAt = Date()
    }

    var kind: RecordKind {
        get { RecordKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    var category: RecordCategory? { RecordCategory(rawValue: categoryRaw) }

    var flow: Flow { Flow(self) }

    /// Re-express every stored rate against a new base currency. Same contract as
    /// `Item.rebase(_:by:)`: original amounts are never touched.
    static func rebase(_ records: [Record], by factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        for record in records {
            record.rateToBase = Flow.safeRate(record.rateToBase) * factor
        }
    }
}

// MARK: - Value snapshot

/// An immutable, Sendable copy of a record's money-relevant fields. All ledger and
/// report maths runs over these, so it is testable without SwiftData and safe to
/// compute off the main actor.
struct Flow: Hashable, Sendable, Identifiable {
    var id: UUID
    var kind: RecordKind
    var amount: Double
    var currencyCode: String
    var rateToBase: Double
    var date: Date
    var accountID: UUID?
    var toAccountID: UUID?
    var toAmount: Double
    var categoryKey: String
    var note: String
    var payee: String
    var labels: [String]

    init(
        id: UUID = UUID(), kind: RecordKind, amount: Double, currencyCode: String = "USD",
        rateToBase: Double = 1, date: Date, accountID: UUID?, toAccountID: UUID? = nil,
        toAmount: Double = 0, categoryKey: String = RecordCategory.otherGeneral.rawValue,
        note: String = "", payee: String = "", labels: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.amount = amount
        self.currencyCode = currencyCode
        self.rateToBase = rateToBase
        self.date = date
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.toAmount = toAmount
        self.categoryKey = categoryKey
        self.note = note
        self.payee = payee
        self.labels = labels
    }

    init(_ record: Record) {
        self.init(
            id: record.uuid, kind: record.kind, amount: record.amount, currencyCode: record.currencyCode,
            rateToBase: record.rateToBase, date: record.date, accountID: record.accountID,
            toAccountID: record.toAccountID, toAmount: record.toAmount, categoryKey: record.categoryRaw,
            note: record.note, payee: record.payee, labels: record.labels
        )
    }

    /// Guarded so a zero, negative or NaN rate can never poison a total.
    static func safeRate(_ rate: Double) -> Double {
        rate.isFinite && rate > 0 ? rate : 1
    }

    var safeAmount: Double { amount.isFinite ? max(0, amount) : 0 }

    /// The magnitude in the user's base currency.
    var baseAmount: Double { safeAmount * Self.safeRate(rateToBase) }

    /// What the destination account receives, in its own currency.
    var creditedAmount: Double {
        toAmount.isFinite && toAmount > 0 ? toAmount : safeAmount
    }

    /// Signed effect on the user's spendable money, in base currency: negative for
    /// spending, positive for income, zero for moving money between own accounts.
    var signedBase: Double {
        switch kind {
        case .expense: -baseAmount
        case .income: baseAmount
        case .transfer: 0
        }
    }

    var category: RecordCategoryDisplay {
        kind == .transfer ? .transfer : RecordCategoryDisplay.resolve(categoryKey)
    }
}

// MARK: - Draft

/// The unmanaged copy the transaction editor binds to — same pattern as `ItemDraft`,
/// so cancelling an edit never persists anything.
struct RecordDraft: Equatable {
    var kind: RecordKind
    var amount: Double
    var currencyCode: String
    var rateToBase: Double
    var date: Date
    var accountID: UUID?
    var toAccountID: UUID?
    var toAmount: Double
    var categoryKey: String
    var note: String
    var payee: String
    var labels: [String]

    init(record: Record) {
        kind = record.kind
        amount = record.amount
        currencyCode = record.currencyCode
        rateToBase = record.rateToBase
        date = record.date
        accountID = record.accountID
        toAccountID = record.toAccountID
        toAmount = record.toAmount
        categoryKey = record.categoryRaw
        note = record.note
        payee = record.payee
        labels = record.labels
    }

    func apply(to record: Record) {
        record.kind = kind
        record.amount = max(0, amount)
        record.currencyCode = currencyCode
        record.rateToBase = Flow.safeRate(rateToBase)
        record.date = date
        record.accountID = accountID
        record.toAccountID = kind == .transfer ? toAccountID : nil
        record.toAmount = kind == .transfer ? max(0, toAmount) : 0
        record.categoryRaw = categoryKey
        record.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        record.payee = payee.trimmingCharacters(in: .whitespacesAndNewlines)
        record.labels = Self.normalisedLabels(labels)
    }

    /// Trimmed, de-duplicated (case-insensitively) and in the order first given.
    static func normalisedLabels(_ labels: [String]) -> [String] {
        var seen = Set<String>()
        return labels.compactMap { raw in
            let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, seen.insert(label.lowercased()).inserted else { return nil }
            return label
        }
    }

    enum Issue: Equatable {
        case noAmount, noAccount, sameAccount, noDestination
    }

    var issues: [Issue] {
        var out: [Issue] = []
        if !(amount.isFinite && amount > 0) { out.append(.noAmount) }
        switch kind {
        case .expense, .income:
            if accountID == nil { out.append(.noAccount) }
        case .transfer:
            if accountID == nil && toAccountID == nil { out.append(.noAccount) }
            if accountID != nil && accountID == toAccountID { out.append(.sameAccount) }
            if accountID != nil && toAccountID == nil { out.append(.noDestination) }
        }
        return out
    }
}

// MARK: - Budget

/// A spending limit over a repeating period, for all expenses or a set of categories.
@Model
final class Budget {
    var uuid: UUID = UUID()
    var name: String = ""
    /// In the user's base currency.
    var limit: Double = 0
    var periodRaw: String = BudgetPeriod.month.rawValue
    /// Category keys (or group keys prefixed `group:`) this budget covers. Empty
    /// means every expense.
    var categoryKeys: [String] = []
    var createdAt: Date = Date()

    init(name: String = "", limit: Double = 0, period: BudgetPeriod = .month, categoryKeys: [String] = []) {
        self.uuid = UUID()
        self.name = name
        self.limit = limit
        self.periodRaw = period.rawValue
        self.categoryKeys = categoryKeys
        self.createdAt = Date()
    }

    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .month }
        set { periodRaw = newValue.rawValue }
    }

    static func rebase(_ budgets: [Budget], by factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        for budget in budgets { budget.limit *= factor }
    }
}

enum BudgetPeriod: String, CaseIterable, Identifiable, Codable {
    case week, month, year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: String(localized: "Weekly", comment: "Budget period")
        case .month: String(localized: "Monthly", comment: "Budget period")
        case .year: String(localized: "Yearly", comment: "Budget period")
        }
    }

    var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date.startOfDay, duration: 86_400)
    }
}

struct BudgetDraft {
    var name: String
    var limit: Double
    var period: BudgetPeriod
    var categoryKeys: [String]

    init(budget: Budget) {
        name = budget.name
        limit = budget.limit
        period = budget.period
        categoryKeys = budget.categoryKeys
    }

    func apply(to budget: Budget) {
        budget.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        budget.limit = max(0, limit)
        budget.period = period
        budget.categoryKeys = categoryKeys
    }

    var isValid: Bool { limit.isFinite && limit > 0 }
}
