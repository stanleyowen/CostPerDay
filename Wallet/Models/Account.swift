import SwiftUI
import SwiftData

/// Where money lives: a bank account, a cash pocket, a card, an e-wallet.
///
/// Transactions point at accounts by `uuid` rather than through a SwiftData
/// relationship. That keeps date-range queries over thousands of records cheap and
/// predicate-friendly, and it means an account can be deleted (or a backup restored
/// out of order) without SwiftData cascading anything behind the user's back.
@Model
final class Account {
    var uuid: UUID = UUID()
    var name: String = ""
    var kindRaw: String = AccountKind.bank.rawValue
    /// Every record in this account is in this currency.
    var currencyCode: String = "USD"
    /// The balance before the first recorded transaction, in `currencyCode`.
    var initialBalance: Double = 0
    /// A `CategoryTint` raw value, or `#RRGGBB` for a colour the user picked
    /// (see `AccountTint`).
    var tintRaw: String = CategoryTint.blue.rawValue
    var isArchived: Bool = false
    /// Savings or investment accounts the user doesn't want counted as spending power.
    var excludeFromStats: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    init(
        name: String = "",
        kind: AccountKind = .bank,
        currencyCode: String = Currency.deviceDefault,
        initialBalance: Double = 0,
        tint: AccountTint = .preset(.blue),
        sortOrder: Int = 0
    ) {
        self.uuid = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.currencyCode = currencyCode
        self.initialBalance = initialBalance
        self.tintRaw = tint.rawValue
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var tint: AccountTint {
        get { AccountTint(rawValue: tintRaw) ?? .preset(.blue) }
        set { tintRaw = newValue.rawValue }
    }

    var displayName: String {
        name.isEmpty ? String(localized: "Untitled account", comment: "Fallback name for an unnamed account") : name
    }
}

/// An account's colour: one of the shared presets, or any colour from the system
/// colour picker. Persisted as a string in `Account.tintRaw` — the preset's raw
/// value, or `#RRGGBB` (sRGB) for a custom colour — so stores and backups made
/// before custom colours existed read back unchanged.
enum AccountTint: Hashable {
    case preset(CategoryTint)
    /// Uppercase `#RRGGBB`.
    case custom(String)

    init?(rawValue: String) {
        if let preset = CategoryTint(rawValue: rawValue) {
            self = .preset(preset)
        } else if let hex = Self.normalisedHex(rawValue) {
            self = .custom(hex)
        } else {
            return nil
        }
    }

    /// A custom tint from any SwiftUI colour; opacity is dropped and wide-gamut
    /// colours are clamped to sRGB.
    init(color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let byte = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        self = .custom(String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue)))
    }

    var rawValue: String {
        switch self {
        case .preset(let preset): preset.rawValue
        case .custom(let hex): hex
        }
    }

    var color: Color {
        switch self {
        case .preset(let preset):
            return preset.color
        case .custom(let hex):
            return Color(hex: UInt32(hex.dropFirst(), radix: 16) ?? 0)
        }
    }

    var isCustom: Bool {
        if case .custom = self { true } else { false }
    }

    private static func normalisedHex(_ raw: String) -> String? {
        let digits = raw.hasPrefix("#") ? raw.dropFirst() : Substring(raw)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits.uppercased()
    }
}

enum AccountKind: String, CaseIterable, Identifiable, Codable {
    case cash, bank, card, eWallet, savings, investment, loan, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cash: String(localized: "Cash", comment: "Account type")
        case .bank: String(localized: "Bank account", comment: "Account type")
        case .card: String(localized: "Credit card", comment: "Account type")
        case .eWallet: String(localized: "E-wallet", comment: "Account type")
        case .savings: String(localized: "Savings", comment: "Account type")
        case .investment: String(localized: "Investment", comment: "Account type")
        case .loan: String(localized: "Loan", comment: "Account type")
        case .other: String(localized: "Other", comment: "Account type")
        }
    }

    var symbol: String {
        switch self {
        case .cash: "banknote.fill"
        case .bank: "building.columns.fill"
        case .card: "creditcard.fill"
        case .eWallet: "wallet.pass.fill"
        case .savings: "dollarsign.circle.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        case .loan: "arrow.uturn.left.circle.fill"
        case .other: "tray.full.fill"
        }
    }

    var defaultTint: CategoryTint {
        switch self {
        case .cash: .green
        case .bank: .blue
        case .card: .indigo
        case .eWallet: .teal
        case .savings: .orange
        case .investment: .purple
        case .loan: .red
        case .other: .gray
        }
    }

    /// A reasonable guess from an account's name, for imports that don't say.
    static func guess(fromName name: String) -> AccountKind {
        let lower = name.lowercased()
        let rules: [(AccountKind, [String])] = [
            (.cash, ["cash", "現金", "现金", "tunai"]),
            (.savings, ["saving", "deposit", "定期", "定存", "tabungan"]),
            (.card, ["credit", "card", "visa", "master", "amex", "信用卡"]),
            (.eWallet, ["pay", "wallet", "ipass", "easycard", "悠遊", "一卡通", "街口", "gopay", "ovo", "dana", "suica"]),
            (.investment, ["invest", "broker", "stock", "證券", "股票"]),
            (.loan, ["loan", "貸款"]),
        ]
        for (kind, needles) in rules where needles.contains(where: { lower.contains($0) }) {
            return kind
        }
        return .bank
    }
}

/// Plain copy of an account's editable fields; the editor binds to this so Cancel
/// never leaves half-made changes behind on the live model.
struct AccountDraft: Equatable {
    var name: String
    var kind: AccountKind
    var currencyCode: String
    var initialBalance: Double
    var tint: AccountTint
    var isArchived: Bool
    var excludeFromStats: Bool

    init(account: Account) {
        name = account.name
        kind = account.kind
        currencyCode = account.currencyCode
        initialBalance = account.initialBalance
        tint = account.tint
        isArchived = account.isArchived
        excludeFromStats = account.excludeFromStats
    }

    func apply(to account: Account) {
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.kind = kind
        account.currencyCode = currencyCode
        account.initialBalance = initialBalance
        account.tint = tint
        account.isArchived = isArchived
        account.excludeFromStats = excludeFromStats
    }
}
