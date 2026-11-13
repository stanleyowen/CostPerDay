import Testing
import Foundation
import SwiftData
@testable import Wallet

/// `LedgerActions.delete` backs both the account editor and the Accounts list swipe.
@MainActor
struct AccountDeletionTests {
    @Test func deletingAnAccountKeepsTransfersAsOutsideTransfers() throws {
        let container = try DataStore.inMemoryContainer()
        let context = container.mainContext
        let doomed = Account(name: "Old card"), kept = Account(name: "Bank")
        context.insert(doomed)
        context.insert(kept)
        let expense = Record(kind: .expense, amount: 10, accountID: doomed.uuid)
        let income = Record(kind: .income, amount: 50, accountID: doomed.uuid)
        let paidOff = Record(kind: .transfer, amount: 200, accountID: kept.uuid, toAccountID: doomed.uuid)
        let topUp = Record(kind: .transfer, amount: 30, accountID: nil, toAccountID: doomed.uuid)
        let unrelated = Record(kind: .expense, amount: 5, accountID: kept.uuid)
        [expense, income, paidOff, topUp, unrelated].forEach(context.insert)
        try context.save()

        #expect(LedgerActions.records(touching: doomed, in: context).count == 4)
        LedgerActions.delete(doomed, in: context)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        #expect(accounts.map(\.uuid) == [kept.uuid])
        let records = try context.fetch(FetchDescriptor<Record>())
        // Income/expense go; the transfer from Bank survives as one to outside Wallet;
        // the outside→card transfer would touch nothing tracked, so it goes too.
        #expect(Set(records.map(\.uuid)) == [paidOff.uuid, unrelated.uuid])
        #expect(paidOff.accountID == kept.uuid)
        #expect(paidOff.toAccountID == nil)
    }
}
