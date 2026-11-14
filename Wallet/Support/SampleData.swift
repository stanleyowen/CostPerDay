#if DEBUG
import Foundation
import SwiftData

/// Debug-only fixtures so the list, charts and detail screens can be exercised
/// without hand-entering a dozen items. Deliberately mixes currencies and sectors.
enum SampleData {
    static func insert(into context: ModelContext) {
        for item in make() { context.insert(item) }
    }

    /// Used by the `-seedSampleData` launch argument, so repeated launches don't pile up copies.
    @MainActor
    static func seedIfEmpty(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        if existing == 0 { insert(into: context) }
        let accounts = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        if accounts == 0 { insertLedger(into: context) }
    }

    /// Four accounts and ~four months of everyday life, so Home, Transactions and
    /// Reports look like real use (README screenshots are taken from this).
    @MainActor
    static func insertLedger(into context: ModelContext) {
        let currency = UserDefaults.standard.string(forKey: "baseCurrency") ?? Currency.deviceDefault
        let bank = Account(name: "Everyday", kind: .bank, currencyCode: currency, initialBalance: 4_250, tint: .preset(.blue), sortOrder: 0)
        let card = Account(name: "Credit card", kind: .card, currencyCode: currency, initialBalance: 0, tint: .preset(.indigo), sortOrder: 1)
        let cash = Account(name: "Cash", kind: .cash, currencyCode: currency, initialBalance: 160, tint: .preset(.green), sortOrder: 2)
        let savings = Account(name: "Savings", kind: .savings, currencyCode: currency, initialBalance: 12_400, tint: .preset(.orange), sortOrder: 3)
        savings.excludeFromStats = true
        for account in [bank, card, cash, savings] { context.insert(account) }

        let calendar = Calendar.current
        // (category, note, amount, account, every N days, labels)
        let pattern: [(RecordCategory, String, Double, Account, Int, [String])] = [
            (.barCafe, "Blue Bottle", 5.5, card, 2, []),
            (.groceries, "Trader Joe's", 46, card, 5, []),
            (.restaurant, "Lunch", 13, cash, 3, []),
            (.publicTransport, "Metro", 2.9, card, 2, []),
            (.restaurant, "Dinner with Sam", 58, card, 9, ["Friends"]),
            (.fuel, "Shell", 41, card, 11, []),
            (.drugstore, "Pharmacy", 18, cash, 16, []),
            (.clothes, "Uniqlo", 64, card, 27, []),
            (.events, "Cinema", 24, card, 19, ["Friends"]),
            (.travel, "Kyoto hotel", 186, card, 45, ["Japan trip"]),
            (.taxi, "Uber", 17, card, 13, []),
        ]
        for day in 0..<125 {
            guard let date = calendar.date(byAdding: .day, value: -day, to: .now) else { continue }
            for (index, entry) in pattern.enumerated() where (day + index * 3) % entry.4 == 0 {
                let jitter = 1 + Double((day * 7 + index * 13) % 20 - 10) / 40
                context.insert(Record(
                    kind: .expense, amount: (entry.2 * jitter * 100).rounded() / 100, currencyCode: currency,
                    date: calendar.date(byAdding: .minute, value: -(index * 97 + 30), to: date) ?? date,
                    accountID: entry.3.uuid, category: entry.0, note: entry.1, labels: entry.5
                ))
            }
            if calendar.component(.day, from: date) == 1 {
                context.insert(Record(kind: .income, amount: 5_200, currencyCode: currency, date: date, accountID: bank.uuid, category: .wage, note: "Salary"))
                context.insert(Record(kind: .expense, amount: 1_650, currencyCode: currency, date: date, accountID: bank.uuid, category: .rent, note: "Rent"))
                context.insert(Record(kind: .expense, amount: 15.99, currencyCode: currency, date: date, accountID: card.uuid, category: .streaming, note: "Netflix"))
                context.insert(Record(kind: .expense, amount: 45, currencyCode: currency, date: date, accountID: bank.uuid, category: .internet, note: "Fiber"))
                context.insert(Record(kind: .transfer, amount: 600, currencyCode: currency, date: date, accountID: bank.uuid, toAccountID: savings.uuid, note: "Monthly saving"))
            }
            if calendar.component(.day, from: date) == 25 {
                context.insert(Record(kind: .transfer, amount: 900, currencyCode: currency, date: date, accountID: bank.uuid, toAccountID: card.uuid, note: "Card payment"))
                context.insert(Record(kind: .income, amount: 320, currencyCode: currency, date: date, accountID: bank.uuid, category: .sale, note: "Sold old camera"))
            }
            if day % 14 == 6 {
                context.insert(Record(kind: .transfer, amount: 100, currencyCode: currency, date: date, accountID: bank.uuid, toAccountID: cash.uuid, note: "ATM"))
            }
        }

        // A purchase that's already being tracked as an item, and one waiting to be.
        if let watchDate = calendar.date(byAdding: .day, value: -38, to: .now) {
            let watch = Record(kind: .expense, amount: 399, currencyCode: currency, date: watchDate, accountID: card.uuid, category: .electronics, note: "Apple Watch")
            context.insert(watch)
            LedgerActions.trackAsItem(watch, in: context)
        }
        if let date = calendar.date(byAdding: .day, value: -6, to: .now) {
            context.insert(Record(kind: .expense, amount: 249, currencyCode: currency, date: date, accountID: card.uuid, category: .electronics, note: "AirPods Pro"))
        }

        context.insert(Budget(name: "Eating out", limit: 450, period: .month, categoryKeys: ["group:food"]))
        context.insert(Budget(name: "Everything", limit: 3_200, period: .month, categoryKeys: []))
        try? context.save()
    }

    /// `-importWalletCSV <path>`: imports a Wallet export at launch, for exercising
    /// the importer and the reports against real data in the simulator.
    static func importWalletIfRequested(container: ModelContainer) {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "-importWalletCSV"), flag + 1 < arguments.count else { return }
        let url = URL(fileURLWithPath: arguments[flag + 1])
        Task { @MainActor in
            do {
                let plan = try WalletImport.plan(from: Data(contentsOf: url))
                let defaults = UserDefaults.standard
                let records = (try? container.mainContext.fetchCount(FetchDescriptor<Record>())) ?? 0
                if records == 0 { defaults.set(plan.referenceCurrency, forKey: "baseCurrency") }
                let base = defaults.string(forKey: "baseCurrency") ?? plan.referenceCurrency
                let outcome = try await LedgerWriter(modelContainer: container).importWallet(plan, factor: 1, baseCurrency: base)
                print("Wallet import: added \(outcome.added), skipped \(outcome.skipped), accounts \(outcome.accountsCreated)")
            } catch {
                print("Wallet import failed: \(error)")
            }
        }
    }

    private static func make() -> [Item] {
        func ago(_ months: Int) -> Date {
            Calendar.current.date(byAdding: .month, value: -months, to: .now) ?? .now
        }

        // Electronics
        let iphone = Item(name: "iPhone 16 Pro", brand: "Apple", category: .phone, price: 1199, currencyCode: "USD", purchaseDate: ago(9), expectedLifetimeMonths: 36)
        let mac = Item(name: "MacBook Pro 14\"", brand: "Apple", category: .laptop, price: 2399, currencyCode: "USD", purchaseDate: ago(28), expectedLifetimeMonths: 60)
        let buds = Item(name: "AirPods Pro 2", brand: "Apple", category: .audio, price: 249, currencyCode: "USD", purchaseDate: ago(20), expectedLifetimeMonths: 36)
        let monitor = Item(name: "Dell U2723QE", brand: "Dell", category: .monitor, price: 549, currencyCode: "USD", purchaseDate: ago(40), expectedLifetimeMonths: 84)

        // Home & furniture
        let mattress = Item(name: "Emma Hybrid Mattress", brand: "Emma", category: .bed, price: 899, currencyCode: "USD", purchaseDate: ago(34), expectedLifetimeMonths: 96)
        let sofa = Item(name: "Söderhamn Sofa", brand: "IKEA", category: .seating, price: 1049, currencyCode: "USD", purchaseDate: ago(52), expectedLifetimeMonths: 120)
        let desk = Item(name: "Standing Desk", brand: "Fully", category: .tableDesk, price: 629, currencyCode: "USD", purchaseDate: ago(30), expectedLifetimeMonths: 120)

        // Appliances & kitchen
        let washer = Item(name: "Washing Machine", brand: "Bosch", category: .largeAppliance, price: 749, currencyCode: "USD", purchaseDate: ago(62), expectedLifetimeMonths: 120)
        let espresso = Item(name: "Espresso Machine", brand: "Breville", category: .smallAppliance, price: 699, currencyCode: "USD", purchaseDate: ago(16), expectedLifetimeMonths: 60)

        // Clothing & personal
        let boots = Item(name: "Leather Boots", brand: "Red Wing", category: .footwear, price: 349, currencyCode: "USD", purchaseDate: ago(26), expectedLifetimeMonths: 60)
        let jacket = Item(name: "Down Jacket", brand: "Patagonia", category: .clothing, price: 279, currencyCode: "USD", purchaseDate: ago(38), expectedLifetimeMonths: 84)
        let glasses = Item(name: "Prescription Glasses", category: .eyewear, price: 420, currencyCode: "USD", purchaseDate: ago(14), expectedLifetimeMonths: 24)

        // Transport, sport & hobby
        let bike = Item(name: "Commuter Bike", brand: "Giant", category: .bicycle, price: 780, currencyCode: "USD", purchaseDate: ago(44), expectedLifetimeMonths: 84)
        let guitar = Item(name: "Acoustic Guitar", brand: "Yamaha", category: .instrument, price: 320, currencyCode: "USD", purchaseDate: ago(70), expectedLifetimeMonths: 180)

        // Bought abroad, with the rate locked in on the day.
        let keeb = Item(name: "Keychron K3", brand: "Keychron", category: .accessory, price: 2790, currencyCode: "TWD", rateToBase: 0.031, purchaseDate: ago(50), expectedLifetimeMonths: 24)
        let camera = Item(name: "Fujifilm X100VI", brand: "Fujifilm", category: .camera, price: 239_800, currencyCode: "JPY", rateToBase: 0.0067, purchaseDate: ago(6), expectedLifetimeMonths: 72)
        let rice = Item(name: "Rice Cooker", brand: "Zojirushi", category: .smallAppliance, price: 2_450_000, currencyCode: "IDR", rateToBase: 0.000061, purchaseDate: ago(11), expectedLifetimeMonths: 84)

        let oldPhone = Item(name: "iPhone 13", brand: "Apple", category: .phone, price: 999, currencyCode: "USD", purchaseDate: ago(48), expectedLifetimeMonths: 36)
        oldPhone.retiredDate = ago(9)
        oldPhone.resaleValue = 320

        return [
            iphone, mac, buds, monitor,
            mattress, sofa, desk,
            washer, espresso,
            boots, jacket, glasses,
            bike, guitar,
            keeb, camera, rice,
            oldPhone,
        ]
    }
}
#endif
