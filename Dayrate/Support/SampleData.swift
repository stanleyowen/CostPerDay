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
    static func seedIfEmpty(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Item>())) ?? 0
        guard existing == 0 else { return }
        insert(into: context)
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
