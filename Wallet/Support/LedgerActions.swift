import Foundation
import SwiftData

/// Writes that more than one surface performs — the editor, Shortcuts, the
/// "track this purchase" suggestion — so they behave identically everywhere.
@MainActor
enum LedgerActions {
    /// The rate to lock for a new record: 1 for base-currency money, otherwise a
    /// live quote, falling back to the last rate used for that currency, then 1.
    static func rate(for currency: String, baseCurrency: String, context: ModelContext) async -> Double {
        guard currency != baseCurrency else { return 1 }
        if case .success(let quote) = await ExchangeRateService.shared.quote(from: currency, to: baseCurrency) {
            return quote.rate
        }
        var descriptor = FetchDescriptor<Record>(
            predicate: #Predicate { $0.currencyCode == currency },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first?.rateToBase).map(Flow.safeRate) ?? 1
    }

    /// Every record that moves money in or out of `account`, transfers included.
    static func records(touching account: Account, in context: ModelContext) -> [Record] {
        let id = account.uuid
        return (try? context.fetch(FetchDescriptor<Record>(predicate: #Predicate { $0.accountID == id || $0.toAccountID == id }))) ?? []
    }

    /// Deletes an account with its income and expenses. Transfers survive as
    /// transfers to or from outside Wallet, so the other account's balance holds.
    static func delete(_ account: Account, in context: ModelContext) {
        let id = account.uuid
        for record in records(touching: account, in: context) {
            if record.kind == .transfer {
                if record.accountID == id { record.accountID = nil }
                if record.toAccountID == id { record.toAccountID = nil }
                if record.accountID == nil && record.toAccountID == nil { context.delete(record) }
            } else {
                context.delete(record)
            }
        }
        context.delete(account)
        try? context.save()
    }

    /// The account new records go to by default: the one used most recently,
    /// else the first active account.
    static func defaultAccount(in context: ModelContext) -> Account? {
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let active = accounts.filter { !$0.isArchived }
        var recent = FetchDescriptor<Record>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        recent.fetchLimit = 1
        if let lastID = (try? context.fetch(recent).first)?.accountID,
           let account = active.first(where: { $0.uuid == lastID }) {
            return account
        }
        return active.sorted { $0.sortOrder < $1.sortOrder }.first
    }

    /// Creates the item that tracks a purchase's lifecycle, prefilled from the
    /// transaction, and links them. The caller presents the item editor so the user
    /// can confirm the name and expected lifetime.
    @discardableResult
    static func trackAsItem(_ record: Record, in context: ModelContext) -> Item {
        let category = record.category?.suggestedItemCategory ?? .other
        let firstLine = record.note.split(separator: "\n").first.map(String.init) ?? ""
        let item = Item(
            name: firstLine.isEmpty ? (record.payee.isEmpty ? (record.category?.label ?? "") : record.payee) : firstLine,
            category: category,
            price: record.amount,
            currencyCode: record.currencyCode,
            rateToBase: Flow.safeRate(record.rateToBase),
            purchaseDate: record.date,
            expectedLifetimeMonths: category.defaultLifetimeMonths
        )
        context.insert(item)
        record.item = item
        record.isItemPurchase = true
        return item
    }

    /// Purchases worth asking about: durable categories, a meaningful amount, not
    /// already tracked or dismissed. Newest first.
    static func lifecycleCandidates(records: [Record], minimumBase: Double, limit: Int = 3) -> [Record] {
        records
            .filter { record in
                guard record.item == nil, !record.lifecycleDismissed, record.kind == .expense,
                      let category = record.category, category.isDurable else { return false }
                return record.flow.baseAmount >= minimumBase
            }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }
}
