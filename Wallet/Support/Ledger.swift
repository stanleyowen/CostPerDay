import Foundation

/// The money-relevant parts of an account, as a Sendable value.
struct AccountRef: Hashable, Sendable, Identifiable {
    var id: UUID
    var currencyCode: String
    var initialBalance: Double
    var excludeFromStats: Bool = false
    var isArchived: Bool = false

    init(id: UUID = UUID(), currencyCode: String, initialBalance: Double = 0, excludeFromStats: Bool = false, isArchived: Bool = false) {
        self.id = id
        self.currencyCode = currencyCode
        self.initialBalance = initialBalance
        self.excludeFromStats = excludeFromStats
        self.isArchived = isArchived
    }

    init(_ account: Account) {
        self.init(
            id: account.uuid, currencyCode: account.currencyCode, initialBalance: account.initialBalance,
            excludeFromStats: account.excludeFromStats, isArchived: account.isArchived
        )
    }
}

/// Balance arithmetic. Pure functions over value types — no SwiftData, no clock.
enum Ledger {
    /// How a single flow moves each account it touches, in that account's currency.
    static func effects(of flow: Flow) -> [(account: UUID, delta: Double)] {
        switch flow.kind {
        case .expense:
            guard let id = flow.accountID else { return [] }
            return [(id, -flow.safeAmount)]
        case .income:
            guard let id = flow.accountID else { return [] }
            return [(id, flow.safeAmount)]
        case .transfer:
            var out: [(UUID, Double)] = []
            if let from = flow.accountID { out.append((from, -flow.safeAmount)) }
            if let to = flow.toAccountID {
                // A transfer in from outside has no source, so its `amount` is already
                // in the destination's currency.
                out.append((to, flow.accountID == nil ? flow.safeAmount : flow.creditedAmount))
            }
            return out
        }
    }

    /// Current balance of every account, in its own currency.
    static func balances(accounts: [AccountRef], flows: [Flow], upTo end: Date? = nil) -> [UUID: Double] {
        var result = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.initialBalance) })
        for flow in flows {
            if let end, flow.date >= end { continue }
            for effect in effects(of: flow) where result[effect.account] != nil {
                result[effect.account, default: 0] += effect.delta
            }
        }
        return result
    }

    /// The most recently locked rate for each currency seen in the records — the best
    /// offline estimate of what a foreign balance is worth in base currency today.
    static func latestRates(flows: [Flow], baseCurrency: String) -> [String: Double] {
        var latest: [String: (date: Date, rate: Double)] = [:]
        for flow in flows where flow.currencyCode != baseCurrency {
            let rate = Flow.safeRate(flow.rateToBase)
            if let existing = latest[flow.currencyCode], existing.date >= flow.date { continue }
            latest[flow.currencyCode] = (flow.date, rate)
        }
        var rates = latest.mapValues(\.rate)
        rates[baseCurrency] = 1
        return rates
    }

    static func toBase(_ amount: Double, currency: String, rates: [String: Double]) -> Double {
        amount * (rates[currency] ?? 1)
    }

    /// Everything the user has, in base currency. Archived accounts still count —
    /// archiving hides an account, it doesn't make its money disappear.
    static func netWorth(accounts: [AccountRef], balances: [UUID: Double], rates: [String: Double]) -> Double {
        accounts.reduce(0) { total, account in
            total + toBase(balances[account.id] ?? 0, currency: account.currencyCode, rates: rates)
        }
    }

    /// Net worth sampled at the end of each bucket, for trend lines. One pass over
    /// the flows, so it stays fast for years of history.
    static func netWorthSeries(
        accounts: [AccountRef], flows: [Flow], rates: [String: Double], buckets: [DateInterval]
    ) -> [(date: Date, value: Double)] {
        guard !buckets.isEmpty else { return [] }
        let currencyOf = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.currencyCode) })
        let sorted = flows.sorted { $0.date < $1.date }
        var running = accounts.reduce(0) { $0 + toBase($1.initialBalance, currency: $1.currencyCode, rates: rates) }
        var index = 0
        var series: [(Date, Double)] = []
        for bucket in buckets {
            while index < sorted.count, sorted[index].date < bucket.end {
                for effect in effects(of: sorted[index]) {
                    guard let code = currencyOf[effect.account] else { continue }
                    running += toBase(effect.delta, currency: code, rates: rates)
                }
                index += 1
            }
            series.append((bucket.start, running))
        }
        return series
    }
}
