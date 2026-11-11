import Testing
import Foundation
@testable import Wallet

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}()

private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

@Suite("Ledger balances")
struct LedgerTests {
    let bank = AccountRef(currencyCode: "TWD", initialBalance: 1_000)
    let cash = AccountRef(currencyCode: "TWD", initialBalance: 0)
    let usd = AccountRef(currencyCode: "USD", initialBalance: 0)

    @Test("Expenses, income and transfers move the right accounts")
    func balances() {
        let flows = [
            Flow(kind: .expense, amount: 100, currencyCode: "TWD", date: day(2026, 1, 1), accountID: bank.id),
            Flow(kind: .income, amount: 500, currencyCode: "TWD", date: day(2026, 1, 2), accountID: bank.id),
            Flow(kind: .transfer, amount: 200, currencyCode: "TWD", date: day(2026, 1, 3), accountID: bank.id, toAccountID: cash.id),
        ]
        let balances = Ledger.balances(accounts: [bank, cash], flows: flows)
        #expect(balances[bank.id] == 1_200)
        #expect(balances[cash.id] == 200)
    }

    @Test("Cross-currency transfers credit the destination in its own currency")
    func crossCurrency() {
        let flow = Flow(kind: .transfer, amount: 33, currencyCode: "TWD", date: day(2026, 1, 1), accountID: bank.id, toAccountID: usd.id, toAmount: 1)
        let balances = Ledger.balances(accounts: [bank, usd], flows: [flow])
        #expect(balances[bank.id] == 967)
        #expect(balances[usd.id] == 1)
    }

    @Test("Transfers to or from outside touch only the tracked side")
    func externalTransfers() {
        let out = Flow(kind: .transfer, amount: 300, currencyCode: "TWD", date: day(2026, 1, 1), accountID: bank.id, toAccountID: nil)
        let into = Flow(kind: .transfer, amount: 50, currencyCode: "TWD", date: day(2026, 1, 2), accountID: nil, toAccountID: cash.id)
        let balances = Ledger.balances(accounts: [bank, cash], flows: [out, into])
        #expect(balances[bank.id] == 700)
        #expect(balances[cash.id] == 50)
    }

    @Test("Transfers are not spending or income")
    func transfersAreNeutral() {
        let flow = Flow(kind: .transfer, amount: 200, date: .now, accountID: bank.id, toAccountID: cash.id)
        #expect(flow.signedBase == 0)
    }

    @Test("Net worth converts foreign balances at the latest locked rate")
    func netWorth() {
        let flows = [
            Flow(kind: .income, amount: 10, currencyCode: "USD", rateToBase: 30, date: day(2026, 1, 1), accountID: usd.id),
            Flow(kind: .income, amount: 10, currencyCode: "USD", rateToBase: 32, date: day(2026, 2, 1), accountID: usd.id),
        ]
        let rates = Ledger.latestRates(flows: flows, baseCurrency: "TWD")
        #expect(rates["USD"] == 32)
        let balances = Ledger.balances(accounts: [bank, usd], flows: flows)
        #expect(Ledger.netWorth(accounts: [bank, usd], balances: balances, rates: rates) == 1_000 + 20 * 32)
    }

    @Test("Net worth series samples the running total at each bucket end")
    func series() {
        let flows = [
            Flow(kind: .expense, amount: 100, currencyCode: "TWD", date: day(2026, 1, 1), accountID: bank.id),
            Flow(kind: .income, amount: 50, currencyCode: "TWD", date: day(2026, 1, 3), accountID: bank.id),
        ]
        let buckets = (1...3).map { DateInterval(start: day(2026, 1, $0, 0), end: day(2026, 1, $0 + 1, 0)) }
        let series = Ledger.netWorthSeries(accounts: [bank], flows: flows, rates: ["TWD": 1], buckets: buckets).map(\.value)
        #expect(series == [900, 900, 950])
    }

    @Test("A corrupt rate or amount can't poison totals")
    func guards() {
        let flow = Flow(kind: .expense, amount: .nan, currencyCode: "USD", rateToBase: -3, date: .now, accountID: nil)
        #expect(flow.baseAmount == 0)
        #expect(Flow.safeRate(.infinity) == 1)
    }
}

@Suite("Reports")
struct ReportTests {
    let account = UUID()
    let savings = UUID()

    private func flows() -> [Flow] {
        [
            Flow(kind: .expense, amount: 100, date: day(2026, 11, 2), accountID: account, categoryKey: RecordCategory.groceries.rawValue, labels: ["Family Mart"]),
            Flow(kind: .expense, amount: 50, date: day(2026, 11, 3), accountID: account, categoryKey: RecordCategory.restaurant.rawValue),
            Flow(kind: .expense, amount: 20, date: day(2026, 11, 3), accountID: account, categoryKey: RecordCategory.taxi.rawValue),
            Flow(kind: .income, amount: 1_000, date: day(2026, 11, 1), accountID: account, categoryKey: RecordCategory.wage.rawValue),
            Flow(kind: .transfer, amount: 400, date: day(2026, 11, 4), accountID: account, toAccountID: savings),
            Flow(kind: .expense, amount: 999, date: day(2026, 11, 5), accountID: savings, categoryKey: RecordCategory.fees.rawValue),
            Flow(kind: .expense, amount: 80, date: day(2026, 10, 2), accountID: account, categoryKey: RecordCategory.groceries.rawValue),
            Flow(kind: .expense, amount: 500, date: day(2026, 10, 20), accountID: account, categoryKey: RecordCategory.groceries.rawValue),
        ]
    }

    @Test("Totals ignore transfers and excluded accounts, and group categories")
    func totals() {
        let period = ReportPeriod.containing(day(2026, 11, 15), range: .month, calendar: calendar)
        let report = Report.build(flows: flows(), period: period, excludedAccounts: [savings], now: day(2026, 11, 30), calendar: calendar)
        #expect(report.expense == 170)
        #expect(report.income == 1_000)
        #expect(report.net == 830)
        #expect(report.expenseByGroup.first?.key == RecordGroup.food.rawValue)
        #expect(report.expenseByGroup.first?.total == 150)
        #expect(report.expenseByCategory.first?.key == RecordCategory.groceries.rawValue)
        #expect(report.byLabel.first?.key == "Family Mart")
        #expect(report.dailyExpense[day(2026, 11, 3, 0)] == 70)
        #expect(abs((report.savingsRate ?? 0) - 0.83) < 0.0001)
        #expect(report.buckets.count == 30)
        #expect(report.buckets.reduce(0) { $0 + $1.expense } == 170)
    }

    @Test("A running period is compared with the same stretch of the previous one")
    func likeForLike() {
        let period = ReportPeriod.containing(day(2026, 11, 5), range: .month, calendar: calendar)
        // On 5 Nov, October counts only up to 5 Oct: the 80 on 2 Oct, not the 500 on 20 Oct.
        let running = Report.build(flows: flows(), period: period, excludedAccounts: [savings], now: day(2026, 11, 5), calendar: calendar)
        #expect(running.previousExpense == 80)
        // Once November is over, the whole of October counts.
        let finished = Report.build(flows: flows(), period: period, excludedAccounts: [savings], now: day(2026, 12, 2), calendar: calendar)
        #expect(finished.previousExpense == 580)
    }

    @Test("Periods navigate by their own unit, including quarters")
    func periods() {
        let month = ReportPeriod.containing(day(2026, 3, 15), range: .month, calendar: calendar)
        #expect(month.shifted(by: -1, calendar: calendar).interval.start == day(2026, 2, 1, 0))
        let quarter = ReportPeriod.containing(day(2026, 5, 15), range: .quarter, calendar: calendar)
        #expect(quarter.interval.start == day(2026, 4, 1, 0))
        #expect(quarter.shifted(by: 1, calendar: calendar).interval.start == day(2026, 7, 1, 0))
        let year = ReportPeriod.containing(day(2026, 5, 15), range: .year, calendar: calendar)
        #expect(year.buckets(calendar: calendar).count == 12)
    }

    @Test("Budgets count only their categories and the current period")
    func budgets() {
        let food = BudgetStatus.evaluate(
            id: UUID(), name: "Food", limit: 120, period: .month, categoryKeys: ["group:food"],
            flows: flows(), now: day(2026, 11, 15), calendar: calendar
        )
        #expect(food.spent == 150)
        #expect(food.isOver)
        let everything = BudgetStatus.evaluate(
            id: UUID(), name: "All", limit: 2_000, period: .month, categoryKeys: [],
            flows: flows(), excludedAccounts: [savings], now: day(2026, 11, 15), calendar: calendar
        )
        #expect(everything.spent == 170)
        #expect(!everything.isOver)
    }
}

@Suite("Amount keypad")
struct AmountExpressionTests {
    private func type(_ keys: String, digits: Int = 2) -> AmountExpression {
        var expression = AmountExpression(maxFractionDigits: digits)
        for key in keys { expression.input(key) }
        return expression
    }

    @Test("Multiplication and division bind tighter than addition")
    func precedence() {
        #expect(type("120+45×2").value == 210)
        #expect(type("100−20÷4").value == 95)
    }

    @Test("Respects the currency's decimal places")
    func decimals() {
        #expect(type("12.345").text == "12.34")
        #expect(type("12.5", digits: 0).text == "125")
        #expect(type("..5").text == "0.5")
    }

    @Test("Trailing operators, leading zeros and division by zero are handled")
    func edges() {
        #expect(type("50+").value == 50)
        #expect(type("0005").text == "5")
        #expect(type("5÷0").value == nil)
        #expect(type("+").isEmpty)
        #expect(type("5+−").text == "5−")
    }

    @Test("Collapsing replaces the sum with its result")
    func collapse() {
        var expression = type("10+2.5")
        expression.collapse()
        #expect(expression.text == "12.5")
        #expect(!expression.hasOperator)
    }
}

@Suite("Suggestions")
struct SuggestionTests {
    let account = UUID()

    private var index: SuggestionIndex {
        SuggestionIndex(flows: [
            Flow(kind: .expense, amount: 195, date: day(2026, 11, 8), accountID: account, categoryKey: RecordCategory.restaurant.rawValue, note: "麥當勞"),
            Flow(kind: .expense, amount: 180, date: day(2026, 11, 1), accountID: account, categoryKey: RecordCategory.restaurant.rawValue, note: "麥當勞"),
            Flow(kind: .expense, amount: 60, date: day(2026, 11, 2), accountID: account, categoryKey: RecordCategory.groceries.rawValue, note: "Family Mart", payee: "FamilyMart"),
            Flow(kind: .income, amount: 12_000, date: day(2026, 11, 3), accountID: account, categoryKey: RecordCategory.grants.rawValue, note: "Salary"),
        ])
    }

    @Test("Known notes and payees pick their usual category")
    func categories() {
        #expect(index.category(note: "麥當勞") == RecordCategory.restaurant.rawValue)
        #expect(index.category(note: "", payee: "familymart") == RecordCategory.groceries.rawValue)
        #expect(index.category(note: "Family Mart Taipei") == RecordCategory.groceries.rawValue)
        #expect(index.category(note: "Something new") == nil)
    }

    @Test("Matches are per type, most-used first, with a typical amount")
    func matches() {
        let expenses = index.matches("", kind: .expense)
        #expect(expenses.first?.note == "麥當勞")
        #expect(expenses.first?.count == 2)
        #expect(expenses.first?.accountID == account)
        #expect(index.matches("sal", kind: .income).first?.note == "Salary")
        #expect(index.matches("sal", kind: .expense).isEmpty)
    }
}

@Suite("Transaction drafts")
struct RecordDraftTests {
    @Test("Edits stay in the draft until applied")
    func isolation() {
        let record = Record(kind: .expense, amount: 50, currencyCode: "TWD", note: "Lunch")
        var draft = RecordDraft(record: record)
        draft.amount = 999
        draft.note = "Changed"
        #expect(record.amount == 50)
        #expect(record.note == "Lunch")
        draft.apply(to: record)
        #expect(record.amount == 999)
        #expect(record.note == "Changed")
    }

    @Test("Labels are trimmed and de-duplicated case-insensitively")
    func labels() {
        #expect(RecordDraft.normalisedLabels([" Trip ", "trip", "", "Food"]) == ["Trip", "Food"])
    }

    @Test("Validation catches missing amount, account and same-account transfers")
    func issues() {
        let a = UUID()
        var draft = RecordDraft(kind: .expense)
        #expect(draft.issues.contains(.noAmount))
        #expect(draft.issues.contains(.noAccount))
        draft.amount = 10
        draft.accountID = a
        #expect(draft.issues.isEmpty)
        draft.kind = .transfer
        draft.toAccountID = a
        #expect(draft.issues == [.sameAccount])
    }

    @Test("Switching an edit away from transfer clears the destination")
    func applyClearsTransferFields() {
        let record = Record(kind: .transfer, amount: 10, accountID: UUID(), toAccountID: UUID(), toAmount: 3)
        var draft = RecordDraft(record: record)
        draft.kind = .expense
        draft.apply(to: record)
        #expect(record.toAccountID == nil)
        #expect(record.toAmount == 0)
    }
}
