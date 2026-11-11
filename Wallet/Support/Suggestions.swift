import Foundation

/// Learns from the user's own history so entry gets faster the more they use the app:
/// type "麥當勞" and the category, account and usual amount fill themselves in.
/// Built from value snapshots; nothing leaves the device.
struct SuggestionIndex: Sendable {
    struct Entry: Hashable, Sendable, Identifiable {
        let note: String
        let kind: RecordKind
        let categoryKey: String
        let accountID: UUID?
        let typicalAmount: Double
        let count: Int
        let lastUsed: Date
        var id: String { "\(kind.rawValue)|\(note.lowercased())|\(categoryKey)" }
    }

    private(set) var entries: [Entry] = []
    private var byNote: [String: Entry] = [:]
    private var byPayee: [String: String] = [:]

    static let empty = SuggestionIndex()

    init() {}

    /// `flows` should be the most recent history first-or-last in any order; only the
    /// latest `window` are used so habits can change.
    init(flows: [Flow], window: Int = 3_000) {
        let recent = flows.sorted { $0.date > $1.date }.prefix(window)
        struct Counter { var count = 0; var amounts: [Double] = []; var last = Date.distantPast; var accounts: [UUID: Int] = [:] }
        var tallies: [String: (note: String, kind: RecordKind, category: String, tally: Counter)] = [:]
        var payeeVotes: [String: [String: Int]] = [:]

        for flow in recent where flow.kind != .transfer {
            let note = flow.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !flow.payee.isEmpty {
                payeeVotes[flow.payee.lowercased(), default: [:]][flow.categoryKey, default: 0] += 1
            }
            guard !note.isEmpty, note.count <= 60, !note.contains("\n") else { continue }
            let key = "\(flow.kind.rawValue)|\(note.lowercased())|\(flow.categoryKey)"
            var entry = tallies[key] ?? (note, flow.kind, flow.categoryKey, Counter())
            entry.tally.count += 1
            if entry.tally.amounts.count < 12 { entry.tally.amounts.append(flow.safeAmount) }
            entry.tally.last = max(entry.tally.last, flow.date)
            if let account = flow.accountID { entry.tally.accounts[account, default: 0] += 1 }
            tallies[key] = entry
        }

        entries = tallies.values.map { value in
            let amounts = value.tally.amounts.sorted()
            return Entry(
                note: value.note,
                kind: value.kind,
                categoryKey: value.category,
                accountID: value.tally.accounts.max { $0.value < $1.value }?.key,
                typicalAmount: amounts.isEmpty ? 0 : amounts[amounts.count / 2],
                count: value.tally.count,
                lastUsed: value.tally.last
            )
        }
        .sorted { ($0.count, $0.lastUsed) > ($1.count, $1.lastUsed) }

        for entry in entries where byNote[entry.note.lowercased()] == nil {
            byNote[entry.note.lowercased()] = entry
        }
        byPayee = payeeVotes.compactMapValues { $0.max { $0.value < $1.value }?.key }
    }

    /// The best-known category for an exact note or payee.
    func category(note: String, payee: String = "") -> String? {
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !n.isEmpty, let entry = byNote[n] { return entry.categoryKey }
        let p = payee.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !p.isEmpty, let key = byPayee[p] { return key }
        // A merchant name often appears inside a longer note ("McDonald's Taipei").
        if !n.isEmpty, n.count >= 3, let entry = entries.first(where: { n.contains($0.note.lowercased()) && $0.note.count >= 3 }) {
            return entry.categoryKey
        }
        return nil
    }

    func entry(note: String) -> Entry? {
        byNote[note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    /// Notes that match what's been typed so far, best first.
    func matches(_ text: String, kind: RecordKind, limit: Int = 6) -> [Entry] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = entries.filter { $0.kind == kind }
        guard !query.isEmpty else { return Array(pool.prefix(limit)) }
        let prefix = pool.filter { $0.note.lowercased().hasPrefix(query.lowercased()) && $0.note.count > query.count }
        let contains = pool.filter { !$0.note.lowercased().hasPrefix(query.lowercased()) && $0.note.localizedCaseInsensitiveContains(query) }
        return Array((prefix + contains).prefix(limit))
    }

    /// Most-used categories for a kind, for the quick row at the top of the picker.
    func frequentCategories(kind: RecordKind, limit: Int = 8) -> [String] {
        var counts: [String: Int] = [:]
        for entry in entries where entry.kind == kind { counts[entry.categoryKey, default: 0] += entry.count }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(limit).map(\.key)
    }
}
