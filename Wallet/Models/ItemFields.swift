import Foundation

/// The subset of an item's data that pricing, validation, and cost math actually need.
/// `Gadget` (the persisted model, aliased as `Item`) conforms to this, and so does
/// `ItemDraft` — a plain, unmanaged copy used while editing. Sharing the protocol
/// means the cost-per-day math is written once and works identically on both, so an
/// edit form can preview costs against a draft without touching the live record.
protocol ItemFields {
    var name: String { get }
    var price: Double { get }
    var currencyCode: String { get }
    var rateToBase: Double { get }
    var purchaseDate: Date { get }
    var expectedLifetimeMonths: Int { get }
    var resaleValue: Double { get }
    var resaleRateToBase: Double { get }
    var retiredDate: Date? { get }
}

// MARK: - Currency conversion

extension ItemFields {
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
}

// MARK: - Cost math
//
// Everything here is expressed in the user's base currency, so items bought in
// different currencies can be summed and compared directly.

extension ItemFields {
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
        let months = min(max(expectedLifetimeMonths, 1), Gadget.maxLifetimeMonths)
        return max(1, Int((Double(months) * 30.4375).rounded()))
    }

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

/// An unmanaged, in-memory copy of an item's editable fields. The edit form binds to
/// this instead of the live `Item`, so Cancel is a true no-op — nothing was ever
/// written to the persisted record — regardless of when SwiftData's autosave happens
/// to run in the background.
struct ItemDraft: ItemFields {
    var name: String
    var brand: String
    var categoryKey: String
    var price: Double
    var currencyCode: String
    var rateToBase: Double
    var purchaseDate: Date
    var expectedLifetimeMonths: Int
    var notes: String
    var resaleValue: Double
    var resaleRateToBase: Double
    /// Not editable in the form — carried along so cost/validation math that depends
    /// on retirement status (e.g. a retired-before-purchase check) stays correct.
    var retiredDate: Date?

    init(item: Item) {
        name = item.name
        brand = item.brand
        categoryKey = item.categoryKey
        price = item.price
        currencyCode = item.currencyCode
        rateToBase = item.rateToBase
        purchaseDate = item.purchaseDate
        expectedLifetimeMonths = item.expectedLifetimeMonths
        notes = item.notes
        resaleValue = item.resaleValue
        resaleRateToBase = item.resaleRateToBase
        retiredDate = item.retiredDate
    }

    /// Writes every editable field back onto the live item. Called only on Save.
    func apply(to item: Item) {
        item.name = name
        item.brand = brand
        item.categoryKey = categoryKey
        item.price = price
        item.currencyCode = currencyCode
        item.rateToBase = rateToBase
        item.purchaseDate = purchaseDate
        item.expectedLifetimeMonths = expectedLifetimeMonths
        item.notes = notes
        item.resaleValue = resaleValue
        item.resaleRateToBase = resaleRateToBase
    }
}
