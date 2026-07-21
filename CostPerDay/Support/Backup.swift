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
            case .unreadable: "That file couldn't be read."
            case .badFormat: "That doesn't look like a CostPerDay backup."
            case .unsupportedVersion(let v): "This backup was made by a newer version of the app (format \(v))."
            case .noPermission: "The app wasn't allowed to open that file."
            }
        }
    }

    static let currentVersion = 2

    // MARK: Export

    static func makeFile(
        gadgets: [Item],
        baseCurrency: String,
        customCategories: [CustomCategory] = []
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
            .appendingPathComponent("CostPerDay-\(stamp).json")
        try encode(file).write(to: url, options: .atomic)
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

    /// Name + price + purchase day is enough to recognise the same purchase twice.
    private static func identity(_ gadget: Item) -> String {
        "\(gadget.name.lowercased())|\(gadget.price)|\(gadget.purchaseDate.startOfDay.timeIntervalSince1970)"
    }

    private static func identity(_ entry: BackupFile.Entry) -> String {
        "\(entry.name.lowercased())|\(entry.price)|\(entry.purchaseDate.startOfDay.timeIntervalSince1970)"
    }
}
