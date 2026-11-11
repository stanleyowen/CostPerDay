import Foundation
import SwiftData

/// `Item` is the name used throughout the app and its UI.
///
/// The underlying class is still called `Gadget` because SwiftData derives the store's
/// entity name from the class name — renaming it would orphan every record already on
/// disk from when the app only tracked electronics. The alias keeps the code reading
/// the way the app now works without putting anyone's existing data at risk.
typealias Item = Gadget

@Model
final class Gadget {
    var name: String = ""
    var brand: String = ""
    /// Either an `ItemCategory` raw value or a `CustomCategory` key. Resolved for
    /// display through `CategoryCatalog`.
    var categoryRaw: String = ItemCategory.other.rawValue
    /// The amount paid, in `currencyCode`.
    var price: Double = 0
    /// The currency this item was actually bought in.
    var currencyCode: String = "USD"
    /// Rate locked at purchase: one unit of `currencyCode` is worth this many base-currency
    /// units. Always 1 when the item was bought in the base currency. Rebased wholesale
    /// when the user changes their base currency — see `Item.rebase(_:by:)`.
    var rateToBase: Double = 1
    var purchaseDate: Date = Date()
    /// How long you expect this to stay in service, in months.
    var expectedLifetimeMonths: Int = 36
    var notes: String = ""
    /// Set when the item is sold, given away, or dies. Freezes the cost clock.
    var retiredDate: Date?
    /// Money recovered on resale, in `currencyCode`. Subtracted from the amortised total.
    var resaleValue: Double = 0
    /// Rate at the time of resale. Zero means "no separate rate recorded" and falls back
    /// to the purchase rate.
    var resaleRateToBase: Double = 0
    var createdAt: Date = Date()

    init(
        name: String = "",
        brand: String = "",
        category: ItemCategory = .other,
        price: Double = 0,
        currencyCode: String = Currency.deviceDefault,
        rateToBase: Double = 1,
        purchaseDate: Date = Date(),
        expectedLifetimeMonths: Int = 36,
        notes: String = ""
    ) {
        self.name = name
        self.brand = brand
        self.categoryRaw = category.rawValue
        self.price = price
        self.currencyCode = currencyCode
        self.rateToBase = rateToBase
        self.purchaseDate = purchaseDate
        self.expectedLifetimeMonths = expectedLifetimeMonths
        self.notes = notes
        self.createdAt = Date()
    }

    /// The stored category pointer. Use `CategoryCatalog.display(for:)` to render it —
    /// it may refer to a built-in category or one the user defined.
    var categoryKey: String {
        get { categoryRaw }
        set { categoryRaw = newValue }
    }

    /// Non-nil only when this item uses a built-in category.
    var builtInCategory: ItemCategory? { ItemCategory(rawValue: categoryRaw) }

    var isRetired: Bool { retiredDate != nil }

    static let maxLifetimeMonths = 600

    /// Re-express every stored rate against a new base currency.
    /// `factor` is how many units of the new base one unit of the old base is worth.
    static func rebase(_ gadgets: [Gadget], by factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        for gadget in gadgets {
            gadget.rateToBase = gadget.effectiveRate * factor
            if gadget.resaleRateToBase > 0 {
                gadget.resaleRateToBase = gadget.resaleRateToBase * factor
            }
        }
    }
}

extension Gadget: ItemFields {}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}
