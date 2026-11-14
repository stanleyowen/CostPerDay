import Testing
import Foundation
import SwiftData
import UIKit
import SwiftUI
@testable import Wallet

@Suite("Ledger models")
struct LedgerModelTests {
    /// A typo in an SF Symbol name renders as nothing at all, silently.
    @Test("Every category, group and account symbol exists")
    func symbolsExist() {
        let names = RecordCategory.allCases.map(\.symbol) + RecordGroup.allCases.map(\.symbol) + AccountKind.allCases.map(\.symbol)
        for name in Set(names) {
            #expect(UIImage(systemName: name) != nil, "missing SF Symbol \(name)")
        }
    }

    @Test("Every group has exactly one general category, and it belongs to that group")
    func generalCategories() {
        for group in RecordGroup.allCases {
            let general = RecordCategory.general(of: group)
            #expect(general.group == group)
            #expect(RecordCategory.inGroup(group).filter(\.isGeneral) == [general])
        }
    }

    @Test("Every Wallet envelope maps to a category of the right kind")
    func envelopeKinds() {
        for (id, category) in WalletImport.envelopeMap {
            // 10000-range envelopes are Wallet's income categories.
            #expect((id >= 10_000 && id < 11_000) == category.isIncome, "envelope \(id) → \(category)")
        }
    }

    @Test("Rebasing rescales locked rates and budget limits, never amounts")
    func rebase() {
        let record = Record(kind: .expense, amount: 100, currencyCode: "USD", rateToBase: 30)
        let budget = Budget(limit: 3_000)
        Record.rebase([record], by: 0.5)
        Budget.rebase([budget], by: 0.5)
        #expect(record.amount == 100)
        #expect(record.rateToBase == 15)
        #expect(budget.limit == 1_500)
    }

    @Test("Account kinds are guessed sensibly from names")
    func accountGuess() {
        #expect(AccountKind.guess(fromName: "Cash (NTD)") == .cash)
        #expect(AccountKind.guess(fromName: "定期存款") == .savings)
        #expect(AccountKind.guess(fromName: "PayPal") == .eWallet)
        #expect(AccountKind.guess(fromName: "Checking (TWD)") == .bank)
    }

    @Test("Upkeep counts linked spending other than the purchase")
    @MainActor
    func upkeep() throws {
        let container = try DataStore.inMemoryContainer()
        let context = container.mainContext
        let purchase = Record(kind: .expense, amount: 30_000, currencyCode: "TWD", date: .now.addingTimeInterval(-86_400 * 9), category: .electronics, note: "iPad")
        context.insert(purchase)
        let item = LedgerActions.trackAsItem(purchase, in: context)
        let repair = Record(kind: .expense, amount: 2_000, currencyCode: "TWD", category: .maintenance, note: "Screen")
        context.insert(repair)
        repair.item = item
        try context.save()

        #expect(item.name == "iPad")
        #expect(item.price == 30_000)
        #expect(purchase.isItemPurchase)
        #expect(item.upkeepInBase == 2_000)
        #expect(abs(item.totalCostPerDay() - 32_000 / 10) < 0.01)
    }

    @Test("Account colours persist as a preset name or #RRGGBB, and nothing else")
    func accountTintRawValues() {
        #expect(AccountTint(rawValue: "teal") == .preset(.teal))
        #expect(AccountTint(rawValue: "#1a2B3c") == .custom("#1A2B3C"))
        #expect(AccountTint(rawValue: "1A2B3C") == .custom("#1A2B3C"))
        for bad in ["", "#12345", "#1234567", "#GGGGGG", "magenta"] {
            #expect(AccountTint(rawValue: bad) == nil, "\(bad)")
        }
        #expect(AccountTint(color: Color(hex: 0xC0FFEE)) == .custom("#C0FFEE"))
        #expect(AccountTint(color: .white) == .custom("#FFFFFF"))

        let account = Account(tint: .custom("#C0FFEE"))
        #expect(account.tintRaw == "#C0FFEE")
        #expect(account.tint == .custom("#C0FFEE"))
        account.tintRaw = "not a colour"
        #expect(account.tint == .preset(.blue))
    }

    @Test("Backup v3 round-trips accounts, transactions, budgets and item links")
    @MainActor
    func backupRoundTrip() throws {
        // Hold the containers: a ModelContext doesn't retain its container, and
        // SwiftData traps if the container is freed while the context is in use.
        let sourceContainer = try DataStore.inMemoryContainer()
        let source = sourceContainer.mainContext
        let account = Account(name: "Bank (TWD)", kind: .bank, currencyCode: "TWD", initialBalance: 500, tint: .custom("#C0FFEE"))
        source.insert(account)
        let record = Record(kind: .expense, amount: 8_400, currencyCode: "TWD", accountID: account.uuid, category: .electronics, note: "Apple Watch", labels: ["Gift"])
        source.insert(record)
        let item = LedgerActions.trackAsItem(record, in: source)
        let budget = Budget(name: "Food", limit: 6_000, categoryKeys: ["group:food"])
        source.insert(budget)
        try source.save()

        let file = Backup.makeFile(gadgets: [item], baseCurrency: "TWD", accounts: [account], records: [record], budgets: [budget])
        let decoded = try Backup.decode(try Backup.encode(file))
        #expect(decoded.formatVersion == 3)

        let targetContainer = try DataStore.inMemoryContainer()
        let target = targetContainer.mainContext
        Backup.restore(decoded, into: target, existing: [])
        let added = Backup.restoreLedger(decoded, into: target, existingAccounts: [], existingRecords: [], existingBudgets: [])
        try target.save()
        #expect(added.accounts == 1 && added.records == 1 && added.budgets == 1)
        #expect(try target.fetch(FetchDescriptor<Account>()).first?.tint == .custom("#C0FFEE"))

        let restored = try #require(try target.fetch(FetchDescriptor<Record>()).first)
        #expect(restored.uuid == record.uuid)
        #expect(restored.labels == ["Gift"])
        #expect(restored.item?.name == "Apple Watch")
        #expect(restored.isItemPurchase)

        // Restoring again adds nothing.
        let again = Backup.restoreLedger(
            decoded, into: target,
            existingAccounts: try target.fetch(FetchDescriptor<Account>()),
            existingRecords: try target.fetch(FetchDescriptor<Record>()),
            existingBudgets: try target.fetch(FetchDescriptor<Budget>())
        )
        #expect(again.accounts == 0 && again.records == 0 && again.budgets == 0)
    }

    @Test("Item-only backups from Dayrate still restore")
    func legacyBackupDecodes() throws {
        let legacy = #"{"formatVersion":2,"exportedAt":"2026-01-01T00:00:00Z","baseCurrency":"USD","gadgets":[]}"#
        let file = try Backup.decode(Data(legacy.utf8))
        #expect(file.records == nil)
        #expect(file.accounts == nil)
    }
}
