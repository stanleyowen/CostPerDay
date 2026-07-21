import Testing
import Foundation
@testable import CostPerDay

/// A fixed "today" so nothing here depends on when the suite runs.
private let now = Date(timeIntervalSince1970: 1_750_000_000) // 2025-06-15 UTC

private func daysBefore(_ count: Int, from reference: Date = now) -> Date {
    Calendar.current.date(byAdding: .day, value: -count, to: reference)!
}

private func gadget(
    price: Double = 1000,
    currency: String = "USD",
    rate: Double = 1,
    boughtDaysAgo: Int = 99,
    lifetimeMonths: Int = 36
) -> Gadget {
    Gadget(
        name: "Test",
        price: price,
        currencyCode: currency,
        rateToBase: rate,
        purchaseDate: daysBefore(boughtDaysAgo),
        expectedLifetimeMonths: lifetimeMonths
    )
}

@Suite("Ownership duration")
struct DaysOwnedTests {
    @Test("The day you buy something counts as day one")
    func dayOfPurchaseIsOne() {
        #expect(gadget(boughtDaysAgo: 0).daysOwned(now: now) == 1)
    }

    @Test("Each elapsed day adds one")
    func countsElapsedDays() {
        #expect(gadget(boughtDaysAgo: 1).daysOwned(now: now) == 2)
        #expect(gadget(boughtDaysAgo: 364).daysOwned(now: now) == 365)
    }

    @Test("A future purchase date never yields zero or negative days")
    func futurePurchaseIsClamped() {
        let future = gadget()
        future.purchaseDate = Calendar.current.date(byAdding: .day, value: 30, to: now)!
        #expect(future.daysOwned(now: now) == 1)
    }

    @Test("Retiring freezes the clock")
    func retirementStopsTheClock() {
        let item = gadget(boughtDaysAgo: 400)
        item.retiredDate = daysBefore(100)
        #expect(item.daysOwned(now: now) == 301)
    }

    @Test("A retirement date before purchase is clamped, not trusted")
    func nonsenseRetirementIsClamped() {
        let item = gadget(boughtDaysAgo: 100)
        item.retiredDate = daysBefore(500)
        #expect(item.daysOwned(now: now) == 1)
    }

    @Test("Spanning a leap day counts the extra day")
    func leapYearIsCounted() {
        let reference = DateComponents(calendar: .current, year: 2024, month: 3, day: 1).date!
        let item = gadget()
        item.purchaseDate = DateComponents(calendar: .current, year: 2024, month: 2, day: 28).date!
        #expect(item.daysOwned(now: reference) == 3) // Feb 28, Feb 29, Mar 1
    }
}

@Suite("Cost per day")
struct CostPerDayTests {
    @Test("Actual cost is price divided by days owned")
    func actualCost() {
        let item = gadget(price: 1000, boughtDaysAgo: 99) // 100 days owned
        #expect(abs(item.actualCostPerDay(now: now) - 10) < 0.0001)
    }

    @Test("Planned cost is price divided by the expected lifetime")
    func plannedCost() {
        let item = gadget(price: 1096.5, lifetimeMonths: 36) // 1096 planned days
        #expect(abs(item.plannedCostPerDay - 1.0004) < 0.001)
    }

    @Test("Holding on longer keeps driving the actual cost down")
    func costFallsOverTime() {
        let young = gadget(price: 1000, boughtDaysAgo: 10)
        let old = gadget(price: 1000, boughtDaysAgo: 1000)
        #expect(young.actualCostPerDay(now: now) > old.actualCostPerDay(now: now))
    }

    @Test("Resale value is subtracted from what the item really cost")
    func resaleReducesCost() {
        let item = gadget(price: 1000, boughtDaysAgo: 99)
        item.resaleValue = 400
        #expect(abs(item.actualCostPerDay(now: now) - 6) < 0.0001)
    }

    @Test("Resale above the price can never make the cost negative")
    func resaleCannotGoNegative() {
        let item = gadget(price: 1000)
        item.resaleValue = 5000
        #expect(item.netCost == 0)
        #expect(item.actualCostPerDay(now: now) == 0)
    }

    @Test("Cost per day is always finite, whatever is stored")
    func neverProducesNaNOrInfinity() {
        let item = gadget(price: 1000)
        item.expectedLifetimeMonths = 0
        item.rateToBase = 0
        #expect(item.plannedCostPerDay.isFinite)
        #expect(item.actualCostPerDay(now: now).isFinite)
        #expect(item.lifetimeProgress(now: now).isFinite)
    }

    @Test("Mode selects between the two readings")
    func modeSelection() {
        let item = gadget(price: 1000, boughtDaysAgo: 99, lifetimeMonths: 36)
        #expect(item.costPerDay(mode: .actual, now: now) == item.actualCostPerDay(now: now))
        #expect(item.costPerDay(mode: .planned, now: now) == item.plannedCostPerDay)
    }
}

@Suite("Paid off")
struct PaidOffTests {
    @Test("Not paid off one day short of the expected life")
    func notYetPaidOff() {
        let item = gadget(lifetimeMonths: 1) // 30 planned days
        item.purchaseDate = daysBefore(28)   // 29 days owned
        #expect(!item.isPaidOff(now: now))
        #expect(item.daysRemaining(now: now) == 1)
    }

    @Test("Paid off exactly on the boundary day")
    func paidOffOnBoundary() {
        let item = gadget(lifetimeMonths: 1)
        item.purchaseDate = daysBefore(29) // 30 days owned == 30 planned
        #expect(item.isPaidOff(now: now))
        #expect(item.daysRemaining(now: now) == 0)
    }

    @Test("Progress passes 1.0 once the item outlives its budget")
    func progressExceedsOne() {
        let item = gadget(lifetimeMonths: 1)
        item.purchaseDate = daysBefore(59)
        #expect(item.lifetimeProgress(now: now) > 1)
    }

    @Test("Days remaining never goes negative")
    func remainingIsFloored() {
        let item = gadget(boughtDaysAgo: 3650, lifetimeMonths: 1)
        #expect(item.daysRemaining(now: now) == 0)
    }

    @Test("Lifetime is capped so an absurd value can't overflow the math")
    func lifetimeIsCapped() {
        let item = gadget()
        item.expectedLifetimeMonths = 999_999
        #expect(item.plannedDays <= Int(Double(Gadget.maxLifetimeMonths) * 30.4375) + 1)
        #expect(item.plannedCostPerDay > 0)
    }
}

@Suite("Currency conversion")
struct CurrencyTests {
    @Test("A gadget in the base currency needs no conversion")
    func baseCurrencyIsUnchanged() {
        let item = gadget(price: 500, currency: "USD", rate: 1)
        #expect(item.priceInBase == 500)
    }

    @Test("A foreign price converts at the rate locked at purchase")
    func foreignConverts() {
        let item = gadget(price: 30_000, currency: "TWD", rate: 0.031)
        #expect(abs(item.priceInBase - 930) < 0.0001)
    }

    @Test("An invalid rate falls back to 1 rather than zeroing the total")
    func invalidRateFallsBack() {
        for bad in [0.0, -2.0, Double.nan, Double.infinity] {
            let item = gadget(price: 100, currency: "JPY", rate: bad)
            #expect(item.priceInBase == 100)
        }
    }

    @Test("Resale uses its own rate when one was recorded")
    func resaleUsesItsOwnRate() {
        let item = gadget(price: 1000, currency: "EUR", rate: 1.10)
        item.resaleValue = 500
        item.resaleRateToBase = 1.20
        #expect(abs(item.netCost - (1100 - 600)) < 0.0001)
    }

    @Test("Resale falls back to the purchase rate when none was recorded")
    func resaleFallsBackToPurchaseRate() {
        let item = gadget(price: 1000, currency: "EUR", rate: 1.10)
        item.resaleValue = 500
        #expect(abs(item.netCost - (1100 - 550)) < 0.0001)
    }

    @Test("Changing base currency re-expresses every locked rate")
    func rebaseScalesRates() {
        let usd = gadget(price: 100, currency: "USD", rate: 1)
        let twd = gadget(price: 3000, currency: "TWD", rate: 0.031)
        Gadget.rebase([usd, twd], by: 32) // 1 USD = 32 TWD

        #expect(abs(usd.priceInBase - 3200) < 0.0001)
        #expect(abs(twd.priceInBase - 2976) < 0.001)
    }

    @Test("Rebasing with a nonsense factor is refused outright")
    func rebaseRejectsBadFactor() {
        let item = gadget(price: 100, rate: 1)
        for bad in [0.0, -1.0, Double.nan] {
            Gadget.rebase([item], by: bad)
            #expect(item.rateToBase == 1)
        }
    }
}

@Suite("Validation")
struct ValidationTests {
    private func issues(_ item: Gadget, base: String = "USD") -> [GadgetValidation.Issue] {
        GadgetValidation.issues(for: item, baseCurrency: base, now: now)
    }

    @Test("A well-formed gadget has no complaints")
    func validGadgetPasses() {
        #expect(issues(gadget()).isEmpty)
    }

    @Test("A blank name is rejected")
    func blankNameRejected() {
        let item = gadget()
        item.name = "   "
        #expect(issues(item).contains { $0.field == .name })
    }

    @Test("Zero and negative prices are rejected")
    func badPriceRejected() {
        for bad in [0.0, -50.0] {
            let item = gadget(price: bad)
            #expect(issues(item).contains { $0.field == .price })
        }
    }

    @Test("A large price in a low-value currency is not mistaken for a typo")
    func largeNativePriceInLowValueCurrencyPasses() {
        // 17,249,000 IDR is roughly $1,050 — an ordinary gadget price, not a typo.
        let item = gadget(price: 17_249_000, currency: "IDR", rate: 0.000061)
        #expect(!issues(item, base: "USD").contains { $0.field == .price })
    }

    @Test("An absurdly large price is still caught, regardless of currency")
    func genuinelyAbsurdPriceIsRejected() {
        let item = gadget(price: 999_999_999_999, currency: "IDR", rate: 0.000061)
        #expect(issues(item, base: "USD").contains { $0.field == .price })
    }

    @Test("A purchase date in the future is rejected")
    func futurePurchaseRejected() {
        let item = gadget()
        item.purchaseDate = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        #expect(issues(item).contains { $0.field == .purchaseDate })
    }

    @Test("Today's date is accepted")
    func todayAccepted() {
        let item = gadget()
        item.purchaseDate = now
        #expect(!issues(item).contains { $0.field == .purchaseDate })
    }

    @Test("Recovering more than you paid is rejected")
    func excessResaleRejected() {
        let item = gadget(price: 500)
        item.resaleValue = 900
        #expect(issues(item).contains { $0.field == .resale })
    }

    @Test("A foreign currency with no rate is rejected")
    func missingRateRejected() {
        let item = gadget(currency: "JPY", rate: 0)
        #expect(issues(item).contains { $0.field == .rate })
    }

    @Test("A foreign currency with a valid rate passes")
    func validRatePasses() {
        #expect(issues(gadget(currency: "JPY", rate: 0.0067)).isEmpty)
    }

    @Test("Retiring before purchase is rejected")
    func earlyRetirementRejected() {
        let item = gadget(boughtDaysAgo: 100)
        item.retiredDate = daysBefore(200)
        #expect(issues(item).contains { $0.field == .retiredDate })
    }

    @Test("Out-of-range lifetimes are rejected at both ends")
    func lifetimeBoundsEnforced() {
        let tooShort = gadget(lifetimeMonths: 0)
        let tooLong = gadget(lifetimeMonths: 1000)
        #expect(issues(tooShort).contains { $0.field == .lifetime })
        #expect(issues(tooLong).contains { $0.field == .lifetime })
    }
}

@Suite("Backup")
struct BackupTests {
    @Test("A backup survives a round trip through JSON")
    func roundTrips() throws {
        let item = gadget(price: 1234.5, currency: "TWD", rate: 0.031, lifetimeMonths: 42)
        item.notes = "impulse buy"
        let file = Backup.makeFile(gadgets: [item], baseCurrency: "USD")

        let decoded = try Backup.decode(try Backup.encode(file))

        #expect(decoded.baseCurrency == "USD")
        #expect(decoded.gadgets.count == 1)
        let entry = try #require(decoded.gadgets.first)
        #expect(entry.price == 1234.5)
        #expect(entry.currencyCode == "TWD")
        #expect(entry.rateToBase == 0.031)
        #expect(entry.expectedLifetimeMonths == 42)
        #expect(entry.notes == "impulse buy")
    }

    @Test("Junk data is rejected with a clear error, not a crash")
    func rejectsJunk() {
        #expect(throws: Backup.Failure.self) {
            try Backup.decode(Data("not json at all".utf8))
        }
    }

    @Test("A backup from a future version is refused")
    func refusesNewerFormat() throws {
        var file = Backup.makeFile(gadgets: [], baseCurrency: "USD")
        file.formatVersion = Backup.currentVersion + 1
        let data = try Backup.encode(file)
        #expect(throws: Backup.Failure.self) {
            try Backup.decode(data)
        }
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test("Non-finite amounts render as a dash instead of 'nan'")
    func handlesNonFinite() {
        #expect(Money.string(.nan, code: "USD") == "—")
        #expect(Money.perDay(.infinity, code: "USD") == "—")
    }

    @Test("Decimal places follow the currency, not a fixed 2")
    func fractionDigitsPerCurrency() {
        #expect(Currency.fractionDigits("JPY") == 0)
        #expect(Currency.fractionDigits("USD") == 2)
        #expect(Currency.fractionDigits("BHD") == 3)
    }

    @Test("Durations read naturally at each magnitude")
    func durationWording() {
        #expect(Duration.fromDays(1) == "1 day")
        #expect(Duration.fromDays(45) == "45 days")
        #expect(Duration.fromDays(365) == "12 mo")
        #expect(Duration.fromDays(1096) == "3 yr")
        #expect(Duration.fromMonths(1) == "1 month")
        #expect(Duration.fromMonths(36) == "3 years")
        #expect(Duration.fromMonths(40) == "3 yr 4 mo")
    }
}
