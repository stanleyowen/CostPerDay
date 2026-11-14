import Foundation
import SwiftData

/// A plain-JSON snapshot of the library. Deliberately independent of the SwiftData
/// schema so a backup taken today still restores after the model changes.
struct BackupFile: Codable {
    var formatVersion = 1
    var exportedAt = Date()
    var baseCurrency: String
    var gadgets: [Entry]
    /// Optional so a v1 backup, written before custom categories existed, still decodes.
    var customCategories: [CustomCategoryEntry]?
    /// v3+: the wallet. Optional so item-only backups (Dayrate, v1–v2) still decode.
    var accounts: [AccountEntry]?
    var records: [RecordEntry]?
    var budgets: [BudgetEntry]?

    struct AccountEntry: Codable {
        var uuid: UUID
        var name: String
        var kind: String
        var currencyCode: String
        var initialBalance: Double
        var tint: String
        var isArchived: Bool
        var excludeFromStats: Bool
        var sortOrder: Int
        var createdAt: Date
    }

    struct RecordEntry: Codable {
        var uuid: UUID
        var kind: String
        var amount: Double
        var currencyCode: String
        var rateToBase: Double
        var date: Date
        var accountID: UUID?
        var toAccountID: UUID?
        var toAmount: Double
        var category: String
        var note: String
        var payee: String
        var labels: [String]
        var importKey: String?
        var lifecycleDismissed: Bool?
        /// Identifies the linked item by the same name|price|day key restore uses.
        var linkedItem: String?
        var isItemPurchase: Bool?
        var createdAt: Date
    }

    struct BudgetEntry: Codable {
        var uuid: UUID
        var name: String
        var limit: Double
        var period: String
        var categoryKeys: [String]
        var createdAt: Date
    }

    struct Entry: Codable {
        var name: String
        var brand: String
        var category: String
        var price: Double
        var currencyCode: String
        var rateToBase: Double
        var purchaseDate: Date
        var expectedLifetimeMonths: Int
        var notes: String
        var retiredDate: Date?
        var resaleValue: Double
        var resaleRateToBase: Double
        var createdAt: Date
    }

    struct CustomCategoryEntry: Codable {
        var uuid: UUID
        var name: String
        var symbolName: String
        var sector: String
        var tint: String
        var defaultLifetimeMonths: Int
        var createdAt: Date
    }
}

enum Backup {
    enum Failure: LocalizedError {
        case unreadable
        case badFormat
        case unsupportedVersion(Int)
        case noPermission

        var errorDescription: String? {
            switch self {
            case .unreadable:
                String(localized: "The file could not be read.", comment: "Backup restore error")
            case .badFormat:
                String(localized: "This file is not a valid Wallet backup.", comment: "Backup restore error")
            case .unsupportedVersion(let v):
                String(localized: "This backup was created by a newer version of the application (format \(v)).", comment: "Backup restore error. The placeholder is a format version number.")
            case .noPermission:
                String(localized: "The application was not permitted to open that file.", comment: "Backup restore error")
            }
        }
    }

    static let currentVersion = 3

    // MARK: Export

    static func makeFile(
        gadgets: [Item],
        baseCurrency: String,
        customCategories: [CustomCategory] = [],
        accounts: [Account] = [],
        records: [Record] = [],
        budgets: [Budget] = []
    ) -> BackupFile {
        var file = makeItemsFile(gadgets: gadgets, baseCurrency: baseCurrency, customCategories: customCategories)
        file.accounts = accounts.map { account in
            BackupFile.AccountEntry(
                uuid: account.uuid, name: account.name, kind: account.kindRaw, currencyCode: account.currencyCode,
                initialBalance: account.initialBalance, tint: account.tintRaw, isArchived: account.isArchived,
                excludeFromStats: account.excludeFromStats, sortOrder: account.sortOrder, createdAt: account.createdAt
            )
        }
        file.records = records.map { record in
            BackupFile.RecordEntry(
                uuid: record.uuid, kind: record.kindRaw, amount: record.amount, currencyCode: record.currencyCode,
                rateToBase: record.rateToBase, date: record.date, accountID: record.accountID,
                toAccountID: record.toAccountID, toAmount: record.toAmount, category: record.categoryRaw,
                note: record.note, payee: record.payee, labels: record.labels, importKey: record.importKey,
                lifecycleDismissed: record.lifecycleDismissed, linkedItem: record.item.map(identity),
                isItemPurchase: record.isItemPurchase, createdAt: record.createdAt
            )
        }
        file.budgets = budgets.map { budget in
            BackupFile.BudgetEntry(
                uuid: budget.uuid, name: budget.name, limit: budget.limit, period: budget.periodRaw,
                categoryKeys: budget.categoryKeys, createdAt: budget.createdAt
            )
        }
        return file
    }

    private static func makeItemsFile(
        gadgets: [Item],
        baseCurrency: String,
        customCategories: [CustomCategory]
    ) -> BackupFile {
        BackupFile(
            formatVersion: currentVersion,
            baseCurrency: baseCurrency,
            gadgets: gadgets.map { gadget in
                BackupFile.Entry(
                    name: gadget.name,
                    brand: gadget.brand,
                    category: gadget.categoryRaw,
                    price: gadget.price,
                    currencyCode: gadget.currencyCode,
                    rateToBase: gadget.rateToBase,
                    purchaseDate: gadget.purchaseDate,
                    expectedLifetimeMonths: gadget.expectedLifetimeMonths,
                    notes: gadget.notes,
                    retiredDate: gadget.retiredDate,
                    resaleValue: gadget.resaleValue,
                    resaleRateToBase: gadget.resaleRateToBase,
                    createdAt: gadget.createdAt
                )
            },
            customCategories: customCategories.map { category in
                BackupFile.CustomCategoryEntry(
                    uuid: category.uuid,
                    name: category.name,
                    symbolName: category.symbolName,
                    sector: category.sectorRaw,
                    tint: category.tintRaw,
                    defaultLifetimeMonths: category.defaultLifetimeMonths,
                    createdAt: category.createdAt
                )
            }
        )
    }

    static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// Writes the backup to a temporary file and returns its URL, ready for a share sheet.
    static func writeTemporary(_ file: BackupFile) throws -> URL {
        let stamp = file.exportedAt.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Wallet-\(stamp).json")
        // Backups hold financial history: keep them encrypted at rest until shared.
        try encode(file).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    // MARK: Import

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file: BackupFile
        do {
            file = try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw Failure.badFormat
        }
        guard file.formatVersion <= currentVersion else {
            throw Failure.unsupportedVersion(file.formatVersion)
        }
        return file
    }

    static func read(from url: URL) throws -> BackupFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
        return try decode(data)
    }

    /// Inserts every entry from a backup, skipping ones that already exist.
    /// Custom categories are restored first so items referring to them land intact.
    /// Returns how many were added and how many were skipped as duplicates.
    @discardableResult
    static func restore(
        _ file: BackupFile,
        into context: ModelContext,
        existing: [Item],
        existingCategories: [CustomCategory] = []
    ) -> (added: Int, skipped: Int, categoriesAdded: Int) {
        var knownCategoryUUIDs = Set(existingCategories.map(\.uuid))
        var categoriesAdded = 0

        for entry in file.customCategories ?? [] {
            guard !knownCategoryUUIDs.contains(entry.uuid) else { continue }
            knownCategoryUUIDs.insert(entry.uuid)

            let category = CustomCategory()
            category.uuid = entry.uuid
            category.name = entry.name
            category.symbolName = entry.symbolName
            category.sectorRaw = Sector(rawValue: entry.sector)?.rawValue ?? Sector.other.rawValue
            category.tintRaw = CategoryTint(rawValue: entry.tint)?.rawValue ?? CategoryTint.gray.rawValue
            category.defaultLifetimeMonths = min(max(entry.defaultLifetimeMonths, 1), Item.maxLifetimeMonths)
            category.createdAt = entry.createdAt
            context.insert(category)
            categoriesAdded += 1
        }

        var seen = Set(existing.map(identity))
        var added = 0
        var skipped = 0

        for entry in file.gadgets {
            let key = identity(entry)
            guard !seen.contains(key) else { skipped += 1; continue }
            seen.insert(key)

            let gadget = Item()
            gadget.name = entry.name
            gadget.brand = entry.brand
            gadget.categoryRaw = restoredCategoryKey(entry.category, knownCategoryUUIDs: knownCategoryUUIDs)
            gadget.price = max(0, entry.price)
            gadget.currencyCode = entry.currencyCode.count == 3 ? entry.currencyCode : file.baseCurrency
            gadget.rateToBase = entry.rateToBase.isFinite && entry.rateToBase > 0 ? entry.rateToBase : 1
            gadget.purchaseDate = entry.purchaseDate
            gadget.expectedLifetimeMonths = min(max(entry.expectedLifetimeMonths, 1), Item.maxLifetimeMonths)
            gadget.notes = entry.notes
            gadget.retiredDate = entry.retiredDate
            gadget.resaleValue = max(0, entry.resaleValue)
            gadget.resaleRateToBase = max(0, entry.resaleRateToBase)
            gadget.createdAt = entry.createdAt
            context.insert(gadget)
            added += 1
        }
        return (added, skipped, categoriesAdded)
    }

    /// Keeps a built-in key, keeps a custom key whose category we actually have, and
    /// falls back to "other" for anything dangling — so a half-complete backup can't
    /// leave items pointing at categories that will never resolve.
    private static func restoredCategoryKey(_ key: String, knownCategoryUUIDs: Set<UUID>) -> String {
        if let builtIn = ItemCategory(rawValue: key) { return builtIn.rawValue }
        if let uuid = CustomCategory.uuid(fromKey: key), knownCategoryUUIDs.contains(uuid) { return key }
        return ItemCategory.other.rawValue
    }

    /// Adds accounts, transactions and budgets from a v3+ backup, skipping any whose
    /// UUID is already present. Run after `restore(_:into:…)` so links to restored
    /// items resolve.
    @discardableResult
    static func restoreLedger(
        _ file: BackupFile,
        into context: ModelContext,
        existingAccounts: [Account],
        existingRecords: [Record],
        existingBudgets: [Budget]
    ) -> (accounts: Int, records: Int, budgets: Int) {
        var accountIDs = Set(existingAccounts.map(\.uuid))
        var addedAccounts = 0
        for entry in file.accounts ?? [] where accountIDs.insert(entry.uuid).inserted {
            let account = Account()
            account.uuid = entry.uuid
            account.name = entry.name
            account.kindRaw = AccountKind(rawValue: entry.kind)?.rawValue ?? AccountKind.other.rawValue
            account.currencyCode = entry.currencyCode.count == 3 ? entry.currencyCode : file.baseCurrency
            account.initialBalance = entry.initialBalance.isFinite ? entry.initialBalance : 0
            account.tintRaw = AccountTint(rawValue: entry.tint)?.rawValue ?? CategoryTint.blue.rawValue
            account.isArchived = entry.isArchived
            account.excludeFromStats = entry.excludeFromStats
            account.sortOrder = entry.sortOrder
            account.createdAt = entry.createdAt
            context.insert(account)
            addedAccounts += 1
        }

        let items = (try? context.fetch(FetchDescriptor<Item>())) ?? []
        let itemsByIdentity = Dictionary(items.map { (identity($0), $0) }, uniquingKeysWith: { first, _ in first })
        var recordIDs = Set(existingRecords.map(\.uuid))
        var addedRecords = 0
        for entry in file.records ?? [] where recordIDs.insert(entry.uuid).inserted {
            guard let kind = RecordKind(rawValue: entry.kind), entry.amount.isFinite else { continue }
            let record = Record()
            record.uuid = entry.uuid
            record.kind = kind
            record.amount = max(0, entry.amount)
            record.currencyCode = entry.currencyCode.count == 3 ? entry.currencyCode : file.baseCurrency
            record.rateToBase = Flow.safeRate(entry.rateToBase)
            record.date = entry.date
            record.accountID = entry.accountID
            record.toAccountID = entry.toAccountID
            record.toAmount = entry.toAmount.isFinite ? max(0, entry.toAmount) : 0
            record.categoryRaw = entry.category
            record.note = entry.note
            record.payee = entry.payee
            record.labels = entry.labels
            record.importKey = entry.importKey
            record.lifecycleDismissed = entry.lifecycleDismissed ?? false
            record.createdAt = entry.createdAt
            context.insert(record)
            if let key = entry.linkedItem, let item = itemsByIdentity[key] {
                record.item = item
                record.isItemPurchase = entry.isItemPurchase ?? false
            }
            addedRecords += 1
        }

        var budgetIDs = Set(existingBudgets.map(\.uuid))
        var addedBudgets = 0
        for entry in file.budgets ?? [] where budgetIDs.insert(entry.uuid).inserted {
            let budget = Budget()
            budget.uuid = entry.uuid
            budget.name = entry.name
            budget.limit = entry.limit.isFinite ? max(0, entry.limit) : 0
            budget.periodRaw = BudgetPeriod(rawValue: entry.period)?.rawValue ?? BudgetPeriod.month.rawValue
            budget.categoryKeys = entry.categoryKeys
            budget.createdAt = entry.createdAt
            context.insert(budget)
            addedBudgets += 1
        }
        return (addedAccounts, addedRecords, addedBudgets)
    }

    /// Name + price + purchase day is enough to recognise the same purchase twice.
    static func identity(_ gadget: Item) -> String {
        "\(gadget.name.lowercased())|\(gadget.price)|\(gadget.purchaseDate.startOfDay.timeIntervalSince1970)"
    }

    private static func identity(_ entry: BackupFile.Entry) -> String {
        "\(entry.name.lowercased())|\(entry.price)|\(entry.purchaseDate.startOfDay.timeIntervalSince1970)"
    }
}
