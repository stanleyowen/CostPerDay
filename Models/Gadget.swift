import Foundation
import SwiftData

@Model
final class Gadget {
    var name: String = ""
    var brand: String = ""
    var categoryRaw: String = GadgetCategory.other.rawValue
    /// The amount paid, in `currencyCode`.
    var price: Double = 0
    /// The currency this gadget was actually bought in.
    var currencyCode: String = "USD"
    /// Rate locked at purchase: one unit of `currencyCode` is worth this many base-currency
    /// units. Always 1 when the gadget was bought in the base currency. Rebased wholesale
    /// when the user changes their base currency — see `Gadget.rebase(_:by:)`.
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
        category: GadgetCategory = .other,
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

    var category: GadgetCategory {
        get { GadgetCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var isRetired: Bool { retiredDate != nil }
}

// MARK: - Currency conversion

extension Gadget {
    /// Guarded so a zero, negative, or NaN rate can never poison every total in the app.
    var effectiveRate: Double {
        rateToBase.isFinite && rateToBase > 0 ? rateToBase : 1
    }

    /// Falls back to the purchase rate when no separate resale rate was recorded.
    var effectiveResaleRate: Double {
        resaleRateToBase.isFinite && resaleRateToBase > 0 ? resaleRateToBase : effectiveRate
    }

    var priceInBase: Double { max(0, price) * effectiveRate }
    var resaleInBase: Double { max(0, resaleValue) * effectiveResaleRate }

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

// MARK: - Cost math
//
// Everything here is expressed in the user's base currency, so gadgets bought in
// different currencies can be summed and compared directly.

extension Gadget {
    /// The amount actually sunk into this item, net of anything recovered on resale.
    var netCost: Double { max(0, priceInBase - resaleInBase) }

    /// Same figure in the currency it was bought in — for showing the original receipt amount.
    var netCostNative: Double { max(0, max(0, price) - max(0, resaleValue)) }

    /// The date the cost clock stops: retirement, or now for items still in use.
    /// A retirement date before the purchase date is clamped, not trusted.
    func clockEnd(now: Date = .now) -> Date {
        if let retiredDate { return max(retiredDate, purchaseDate) }
        return max(now, purchaseDate)
    }

    /// Days the item has actually been owned. Day one counts, so this is never zero —
    /// which is also what keeps every division below safe.
    func daysOwned(now: Date = .now) -> Int {
        let days = Calendar.current.dateComponents(
            [.day], from: purchaseDate.startOfDay, to: clockEnd(now: now).startOfDay
        ).day ?? 0
        return max(1, days + 1)
    }

    /// Days the item is *planned* to last, derived from the expected lifetime in months.
    var plannedDays: Int {
        let months = min(max(expectedLifetimeMonths, 1), Self.maxLifetimeMonths)
        return max(1, Int((Double(months) * 30.4375).rounded()))
    }

    static let maxLifetimeMonths = 600

    /// What it has cost per day so far. Keeps falling for as long as you keep using it.
    func actualCostPerDay(now: Date = .now) -> Double {
        netCost / Double(daysOwned(now: now))
    }

    /// What you budgeted per day when you bought it. A constant.
    var plannedCostPerDay: Double {
        netCost / Double(plannedDays)
    }

    func costPerDay(mode: CostMode, now: Date = .now) -> Double {
        switch mode {
        case .actual: actualCostPerDay(now: now)
        case .planned: plannedCostPerDay
        }
    }

    /// 0…1 while inside the expected lifetime, >1 once the item has outlived it.
    func lifetimeProgress(now: Date = .now) -> Double {
        Double(daysOwned(now: now)) / Double(plannedDays)
    }

    /// True once the item has outlived what you budgeted for — every extra day is free.
    func isPaidOff(now: Date = .now) -> Bool {
        daysOwned(now: now) >= plannedDays
    }

    func daysRemaining(now: Date = .now) -> Int {
        max(0, plannedDays - daysOwned(now: now))
    }

    var expectedEndDate: Date {
        Calendar.current.date(byAdding: .day, value: plannedDays, to: purchaseDate) ?? purchaseDate
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}
