#if DEBUG
import Foundation
import SwiftData

/// Debug-only fixtures so the list, charts and detail screens can be exercised
/// without hand-entering a dozen gadgets. Deliberately mixes currencies.
enum SampleData {
    static func insert(into context: ModelContext) {
        for gadget in make() { context.insert(gadget) }
    }

    /// Used by the `-seedSampleData` launch argument, so repeated launches don't pile up copies.
    static func seedIfEmpty(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Gadget>())) ?? 0
        guard existing == 0 else { return }
        insert(into: context)
    }

    private static func make() -> [Gadget] {
        func ago(_ months: Int) -> Date {
            Calendar.current.date(byAdding: .month, value: -months, to: .now) ?? .now
        }

        let iphone = Gadget(name: "iPhone 16 Pro", brand: "Apple", category: .phone, price: 1199, currencyCode: "USD", purchaseDate: ago(9), expectedLifetimeMonths: 36)
        let mac = Gadget(name: "MacBook Pro 14\"", brand: "Apple", category: .laptop, price: 2399, currencyCode: "USD", purchaseDate: ago(28), expectedLifetimeMonths: 60)
        let buds = Gadget(name: "AirPods Pro 2", brand: "Apple", category: .audio, price: 249, currencyCode: "USD", purchaseDate: ago(20), expectedLifetimeMonths: 36)
        let watch = Gadget(name: "Apple Watch Ultra", brand: "Apple", category: .wearable, price: 799, currencyCode: "USD", purchaseDate: ago(4), expectedLifetimeMonths: 48)
        let monitor = Gadget(name: "Dell U2723QE", brand: "Dell", category: .monitor, price: 549, currencyCode: "USD", purchaseDate: ago(40), expectedLifetimeMonths: 84)
        let deck = Gadget(name: "Steam Deck OLED", brand: "Valve", category: .gaming, price: 549, currencyCode: "USD", purchaseDate: ago(14), expectedLifetimeMonths: 60)

        // Bought abroad, with the rate locked in on the day.
        let keeb = Gadget(name: "Keychron K3", brand: "Keychron", category: .accessory, price: 2790, currencyCode: "TWD", rateToBase: 0.031, purchaseDate: ago(50), expectedLifetimeMonths: 24)
        let camera = Gadget(name: "Fujifilm X100VI", brand: "Fujifilm", category: .camera, price: 239_800, currencyCode: "JPY", rateToBase: 0.0067, purchaseDate: ago(6), expectedLifetimeMonths: 72)

        let oldPhone = Gadget(name: "iPhone 13", brand: "Apple", category: .phone, price: 999, currencyCode: "USD", purchaseDate: ago(48), expectedLifetimeMonths: 36)
        oldPhone.retiredDate = ago(9)
        oldPhone.resaleValue = 320

        return [iphone, mac, buds, watch, monitor, keeb, deck, camera, oldPhone]
    }
}
#endif
