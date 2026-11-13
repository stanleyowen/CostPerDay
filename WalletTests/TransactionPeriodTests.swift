import Testing
import Foundation
@testable import Wallet

/// The periods offered by the filter bar at the bottom of transaction lists.
struct TransactionPeriodTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    /// Saturday 14 November 2026, midday.
    private var now: Date { date(2026, 11, 14) }

    private func interval(_ period: TransactionPeriod) -> DateInterval? {
        period.interval(now: now, calendar: calendar)
    }

    @Test func allTimeHasNoBounds() {
        #expect(interval(.all) == nil)
    }

    @Test func rollingWindowsEndTodayAndIncludeIt() {
        let tomorrow = date(2026, 11, 15, 0)
        #expect(interval(.recent(.days7)) == DateInterval(start: date(2026, 11, 8, 0), end: tomorrow))
        #expect(interval(.recent(.days30)) == DateInterval(start: date(2026, 10, 16, 0), end: tomorrow))
        #expect(interval(.recent(.weeks12))?.start == date(2026, 8, 23, 0))
        #expect(interval(.recent(.months6))?.start == date(2026, 5, 15, 0))
        #expect(interval(.recent(.year1))?.start == date(2025, 11, 15, 0))
    }

    @Test func calendarPeriodsStepBackButNotPastNow() {
        #expect(interval(.calendar(.month, offset: 0)) == DateInterval(start: date(2026, 11, 1, 0), end: date(2026, 12, 1, 0)))
        #expect(interval(.calendar(.month, offset: -1)) == DateInterval(start: date(2026, 10, 1, 0), end: date(2026, 11, 1, 0)))
        #expect(interval(.calendar(.week, offset: 0))?.start == date(2026, 11, 9, 0))
        #expect(interval(.calendar(.day, offset: -1)) == DateInterval(start: date(2026, 11, 13, 0), end: date(2026, 11, 14, 0)))
        #expect(interval(.calendar(.year, offset: -2))?.start == date(2024, 1, 1, 0))

        let thisMonth = TransactionPeriod.calendar(.month, offset: 0)
        #expect(thisMonth.stepped(by: -1) == .calendar(.month, offset: -1))
        #expect(thisMonth.stepped(by: 1) == thisMonth)
        #expect(TransactionPeriod.recent(.days7).stepped(by: -1) == .recent(.days7))
    }

    @Test func customRangesCoverWholeDaysInEitherOrder() {
        let range = DateInterval(start: date(2026, 11, 8, 0), end: date(2026, 11, 15, 0))
        #expect(interval(.custom(start: date(2026, 11, 8, 18), end: date(2026, 11, 14, 9))) == range)
        #expect(interval(.custom(start: date(2026, 11, 14), end: date(2026, 11, 8))) == range)
    }

    @Test func currentPeriodsUseTheirOwnNames() {
        #expect(TransactionPeriod.calendar(.month, offset: 0).label(now: now, calendar: calendar) == String(localized: "This month", comment: "Period filter"))
        #expect(TransactionPeriod.calendar(.month, offset: -1).label(now: now, calendar: calendar) == String(localized: "Last month", comment: "Period filter"))
        #expect(!TransactionPeriod.calendar(.month, offset: -3).label(now: now, calendar: calendar).isEmpty)
    }

    @Test func filtersCountThePeriodSeparatelyFromTheRest() {
        var filter = TransactionFilter()
        filter.period = .recent(.days30)
        #expect(filter.activeCount == 1)
        #expect(filter.detailCount == 0)
        filter.kinds = [.expense]
        filter.labels = ["Trip"]
        #expect(filter.detailCount == 2)
        filter.clearDetails()
        #expect(filter.detailCount == 0)
        #expect(filter.period == .recent(.days30))
    }
}
