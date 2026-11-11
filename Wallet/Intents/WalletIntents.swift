import AppIntents
import SwiftData
import Foundation

// MARK: - Entities

enum IntentRecordKind: String, AppEnum {
    case expense, income

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Transaction Type"
    static let caseDisplayRepresentations: [IntentRecordKind: DisplayRepresentation] = [
        .expense: DisplayRepresentation(title: "Expense", image: .init(systemName: "arrow.up.right")),
        .income: DisplayRepresentation(title: "Income", image: .init(systemName: "arrow.down.left")),
    ]

    var kind: RecordKind { self == .income ? .income : .expense }
}

enum IntentPeriod: String, AppEnum {
    case today, week, month, year

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Period"
    static let caseDisplayRepresentations: [IntentPeriod: DisplayRepresentation] = [
        .today: "Today", .week: "This Week", .month: "This Month", .year: "This Year",
    ]

    var preset: PeriodPreset {
        switch self {
        case .today: .today
        case .week: .thisWeek
        case .month: .thisMonth
        case .year: .thisYear
        }
    }
}

struct AccountEntity: AppEntity, Identifiable {
    let id: UUID
    let name: String
    let currencyCode: String
    let kindSymbol: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Account"
    static let defaultQuery = AccountEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(currencyCode)", image: .init(systemName: kindSymbol))
    }

    init(_ account: Account) {
        id = account.uuid
        name = account.displayName
        currencyCode = account.currencyCode
        kindSymbol = account.kind.symbol
    }
}

struct AccountEntityQuery: EntityStringQuery {
    @MainActor
    private func all() -> [AccountEntity] {
        guard let context = DataStore.shared.container?.mainContext else { return [] }
        let accounts = (try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        return accounts.filter { !$0.isArchived }.map(AccountEntity.init)
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [AccountEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [AccountEntity] {
        all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [AccountEntity] { all() }
}

struct CategoryEntity: AppEntity, Identifiable {
    let id: String
    let name: String
    let symbol: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let defaultQuery = CategoryEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(_ category: RecordCategory) {
        id = category.rawValue
        name = category.label
        symbol = category.symbol
    }
}

struct CategoryEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
        identifiers.compactMap(RecordCategory.init(rawValue:)).map(CategoryEntity.init)
    }

    func entities(matching string: String) async throws -> [CategoryEntity] {
        RecordCategory.allCases
            .filter { $0.label.localizedCaseInsensitiveContains(string) || $0.group.label.localizedCaseInsensitiveContains(string) }
            .map(CategoryEntity.init)
    }

    func suggestedEntities() async throws -> [CategoryEntity] {
        RecordCategory.allCases.map(CategoryEntity.init)
    }
}

enum WalletIntentError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable, noAccount, invalidAmount

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable: "Wallet's data couldn't be opened."
        case .noAccount: "Add an account in Wallet first."
        case .invalidAmount: "The amount must be greater than zero."
        }
    }
}

// MARK: - Add transaction

/// The workhorse: log an expense or income from Shortcuts, Siri, or an Apple Pay
/// automation. Category is optional — when it's left out, Wallet picks the one you
/// usually use for that note or merchant.
struct AddTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Transaction"
    static let description = IntentDescription(
        "Records an expense or income in Wallet. If no category is given, Wallet picks the one you usually use for that note or merchant.",
        categoryName: "Transactions"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Amount", inclusiveRange: (0.01, 1_000_000_000))
    var amount: Double

    @Parameter(title: "Type", default: .expense)
    var kind: IntentRecordKind

    @Parameter(title: "Account", description: "Leave empty to use the account you used most recently.")
    var account: AccountEntity?

    @Parameter(title: "Category")
    var category: CategoryEntity?

    @Parameter(title: "Note")
    var note: String?

    @Parameter(title: "Merchant", description: "For example, the merchant from an Apple Pay automation.")
    var merchant: String?

    @Parameter(title: "Date", description: "Leave empty for now.")
    var date: Date?

    @Parameter(title: "Labels")
    var labels: [String]?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$kind) of \(\.$amount) to \(\.$account)") {
            \.$category
            \.$note
            \.$merchant
            \.$date
            \.$labels
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard amount.isFinite, amount > 0 else { throw WalletIntentError.invalidAmount }
        guard let context = DataStore.shared.container?.mainContext else { throw WalletIntentError.unavailable }
        let accounts = try context.fetch(FetchDescriptor<Account>())
        guard let target = account.flatMap({ entity in accounts.first { $0.uuid == entity.id } })
                ?? LedgerActions.defaultAccount(in: context) else {
            throw WalletIntentError.noAccount
        }
        let baseCurrency = UserDefaults.standard.string(forKey: "baseCurrency") ?? Currency.deviceDefault
        let noteText = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let merchantText = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let categoryKey: String
        if let category {
            categoryKey = category.id
        } else {
            var recent = FetchDescriptor<Record>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            recent.fetchLimit = 3_000
            let index = SuggestionIndex(flows: try context.fetch(recent).map(\.flow))
            categoryKey = index.category(note: noteText.isEmpty ? merchantText : noteText, payee: merchantText)
                ?? (kind == .income ? RecordCategory.incomeGeneral.rawValue : RecordCategory.unknown.rawValue)
        }

        let rate = await LedgerActions.rate(for: target.currencyCode, baseCurrency: baseCurrency, context: context)
        let digits = Currency.fractionDigits(target.currencyCode)
        let scale = pow(10, Double(digits))
        let record = Record(
            kind: kind.kind,
            amount: (amount * scale).rounded() / scale,
            currencyCode: target.currencyCode,
            rateToBase: rate,
            date: date ?? .now,
            accountID: target.uuid,
            category: RecordCategory(rawValue: categoryKey) ?? .unknown,
            note: noteText,
            payee: merchantText,
            labels: RecordDraft.normalisedLabels(labels ?? [])
        )
        record.categoryRaw = categoryKey
        context.insert(record)
        try context.save()

        let flows = try context.fetch(FetchDescriptor<Record>()).map(\.flow)
        let balance = Ledger.balances(accounts: [AccountRef(target)], flows: flows)[target.uuid] ?? 0
        let amountText = Money.exact(record.amount, code: target.currencyCode)
        let categoryText = RecordCategoryDisplay.resolve(categoryKey).label
        let balanceText = Money.exact(balance, code: target.currencyCode)
        let summary: LocalizedStringResource = kind == .income
            ? "Added \(amountText) income to \(target.displayName) · \(categoryText). Balance: \(balanceText)."
            : "Added \(amountText) to \(target.displayName) · \(categoryText). Balance: \(balanceText)."
        return .result(value: balance, dialog: IntentDialog(summary))
    }
}

// MARK: - Queries

struct GetBalanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Balance"
    static let description = IntentDescription("Returns the balance of an account, or your total across all accounts.", categoryName: "Balances")

    @Parameter(title: "Account", description: "Leave empty for the total of all accounts, in your main currency.")
    var account: AccountEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get balance of \(\.$account)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard let context = DataStore.shared.container?.mainContext else { throw WalletIntentError.unavailable }
        let baseCurrency = UserDefaults.standard.string(forKey: "baseCurrency") ?? Currency.deviceDefault
        let ledger = LedgerSnapshot(
            accounts: try context.fetch(FetchDescriptor<Account>()),
            records: try context.fetch(FetchDescriptor<Record>()),
            baseCurrency: baseCurrency
        )
        if let entity = account, let target = ledger.account(entity.id) {
            let balance = ledger.balance(of: target)
            return .result(value: balance, dialog: "\(target.displayName): \(Money.exact(balance, code: target.currencyCode))")
        }
        return .result(value: ledger.netWorth, dialog: "Total balance: \(Money.exact(ledger.netWorth, code: baseCurrency))")
    }
}

struct SpendingSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Spending"
    static let description = IntentDescription("Returns how much you've spent in a period, optionally for one category.", categoryName: "Reports")

    @Parameter(title: "Period", default: .month)
    var period: IntentPeriod

    @Parameter(title: "Category")
    var category: CategoryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get spending for \(\.$period)") { \.$category }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard let context = DataStore.shared.container?.mainContext else { throw WalletIntentError.unavailable }
        let baseCurrency = UserDefaults.standard.string(forKey: "baseCurrency") ?? Currency.deviceDefault
        guard let interval = period.preset.interval() else { return .result(value: 0, dialog: "Nothing recorded.") }
        let start = interval.start, end = interval.end
        let records = try context.fetch(FetchDescriptor<Record>(predicate: #Predicate { $0.date >= start && $0.date < end }))
        let excluded = Set(try context.fetch(FetchDescriptor<Account>()).filter(\.excludeFromStats).map(\.uuid))
        let total = records.map(\.flow).reduce(0.0) { sum, flow in
            guard flow.kind == .expense else { return sum }
            if let id = flow.accountID, excluded.contains(id) { return sum }
            if let category, flow.categoryKey != category.id { return sum }
            return sum + flow.baseAmount
        }
        let amount = Money.exact(total, code: baseCurrency)
        let scope = category?.name ?? String(localized: "everything", comment: "Spending summary scope when no category is given")
        return .result(value: total, dialog: "\(period.preset.label): \(amount) on \(scope).")
    }
}

// MARK: - Open the app

struct NewTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "New Transaction"
    static let description = IntentDescription("Opens Wallet ready to record a transaction.", categoryName: "Transactions")
    static let openAppWhenRun = true

    @Parameter(title: "Type", default: .expense)
    var kind: IntentRecordKind

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.compose(kind.kind)
        return .result()
    }
}

// MARK: - Siri & Spotlight

struct WalletShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTransactionIntent(),
            phrases: [
                "Add an expense in \(.applicationName)",
                "Log spending in \(.applicationName)",
                "Record a transaction in \(.applicationName)",
            ],
            shortTitle: "Add Transaction",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: NewTransactionIntent(),
            phrases: ["New \(.applicationName) transaction", "Open \(.applicationName) to add a transaction"],
            shortTitle: "New Transaction",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: GetBalanceIntent(),
            phrases: ["What's my balance in \(.applicationName)", "Check my \(.applicationName) balance"],
            shortTitle: "Balance",
            systemImageName: "banknote.fill"
        )
        AppShortcut(
            intent: SpendingSummaryIntent(),
            phrases: ["How much did I spend in \(.applicationName)", "My spending in \(.applicationName)"],
            shortTitle: "Spending",
            systemImageName: "chart.pie.fill"
        )
    }
}
