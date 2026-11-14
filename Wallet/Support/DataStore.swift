import Foundation
import SwiftData

/// Owns the one SwiftData container the app and its App Intents share. If the real
/// store can't be opened — a corrupt file, a schema it can't migrate, no disk
/// space — it falls back to an in-memory store and says so, rather than killing
/// the app on launch.
@MainActor
@Observable
final class DataStore {
    static let shared = DataStore()

    static let models: [any PersistentModel.Type] = [Item.self, CustomCategory.self, Account.self, Record.self, Budget.self]

    private(set) var container: ModelContainer?
    private(set) var isTemporary = false
    private(set) var failureMessage: String?

    private init() {
        let schema = Schema(Self.models)
        do {
            container = try ModelContainer(for: schema)
        } catch {
            let firstFailure = error.localizedDescription
            do {
                container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                isTemporary = true
            } catch {
                failureMessage = firstFailure
            }
        }
        container?.mainContext.undoManager = UndoManager()

        #if DEBUG
        if let context = container?.mainContext, CommandLine.arguments.contains("-seedSampleData") {
            SampleData.seedIfEmpty(in: context)
        }
        if let container {
            SampleData.importWalletIfRequested(container: container)
        }
        #endif
    }

    /// A container for tests and previews that never touches disk.
    static func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}

/// Bulk writes off the main actor, so importing years of history never stalls the UI.
@ModelActor
actor LedgerWriter {
    struct ImportOutcome: Sendable {
        var added: Int
        var skipped: Int
        var accountsCreated: Int
    }

    /// Inserts a Wallet import plan. Existing accounts are matched by name; records
    /// already imported (same `importKey`) are skipped, so this is safe to repeat.
    /// `factor` converts Wallet's reference currency into the user's base currency.
    func importWallet(_ plan: WalletImport.Plan, factor: Double, baseCurrency: String) throws -> ImportOutcome {
        let factor = factor.isFinite && factor > 0 ? factor : 1

        var accounts = try modelContext.fetch(FetchDescriptor<Account>())
        var byName = Dictionary(accounts.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var created = 0
        var nextOrder = (accounts.map(\.sortOrder).max() ?? -1) + 1
        for planned in plan.accounts where byName[planned.name.lowercased()] == nil {
            let account = Account(
                name: planned.name, kind: planned.kind, currencyCode: planned.currency,
                tint: .preset(planned.kind.defaultTint), sortOrder: nextOrder
            )
            nextOrder += 1
            modelContext.insert(account)
            accounts.append(account)
            byName[planned.name.lowercased()] = account
            created += 1
        }

        var existingKeys = Set<String>()
        var keyed = FetchDescriptor<Record>(predicate: #Predicate { $0.importKey != nil })
        keyed.propertiesToFetch = [\.importKey]
        for record in try modelContext.fetch(keyed) {
            if let key = record.importKey { existingKeys.insert(key) }
        }

        var added = 0, skipped = 0
        for (index, planned) in plan.records.enumerated() {
            guard !existingKeys.contains(planned.key) else { skipped += 1; continue }
            existingKeys.insert(planned.key)
            let rate = planned.currency == baseCurrency ? 1 : planned.refRate * factor
            let record = Record(
                kind: planned.kind,
                amount: planned.amount,
                currencyCode: planned.currency,
                rateToBase: rate,
                date: planned.date,
                accountID: planned.account.flatMap { byName[$0.lowercased()]?.uuid },
                toAccountID: planned.toAccount.flatMap { byName[$0.lowercased()]?.uuid },
                toAmount: planned.toAmount,
                category: planned.category,
                note: planned.note,
                payee: planned.payee,
                labels: planned.labels
            )
            record.importKey = planned.key
            modelContext.insert(record)
            added += 1
            if index % 500 == 499 { try modelContext.save() }
        }
        try modelContext.save()
        return ImportOutcome(added: added, skipped: skipped, accountsCreated: created)
    }
}
