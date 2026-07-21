import Foundation
import SwiftData

/// A plain-JSON snapshot of the library. Deliberately independent of the SwiftData
/// schema so a backup taken today still restores after the model changes.
struct BackupFile: Codable {
    var formatVersion = 1
    var exportedAt = Date()
    var baseCurrency: String
    var gadgets: [Entry]

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

    static let currentVersion = 1

    // MARK: Export

    static func makeFile(gadgets: [Gadget], baseCurrency: String) -> BackupFile {
        BackupFile(
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
    /// Returns how many were added and how many were skipped as duplicates.
    @discardableResult
    static func restore(_ file: BackupFile, into context: ModelContext, existing: [Gadget]) -> (added: Int, skipped: Int) {
        var seen = Set(existing.map(identity))
        var added = 0
        var skipped = 0

        for entry in file.gadgets {
            let key = identity(entry)
            guard !seen.contains(key) else { skipped += 1; continue }
            seen.insert(key)

            let gadget = Gadget()
            gadget.name = entry.name
            gadget.brand = entry.brand
            gadget.categoryRaw = GadgetCategory(rawValue: entry.category)?.rawValue ?? GadgetCategory.other.rawValue
            gadget.price = max(0, entry.price)
            gadget.currencyCode = entry.currencyCode.count == 3 ? entry.currencyCode : file.baseCurrency
            gadget.rateToBase = entry.rateToBase.isFinite && entry.rateToBase > 0 ? entry.rateToBase : 1
            gadget.purchaseDate = entry.purchaseDate
            gadget.expectedLifetimeMonths = min(max(entry.expectedLifetimeMonths, 1), Gadget.maxLifetimeMonths)
            gadget.notes = entry.notes
            gadget.retiredDate = entry.retiredDate
            gadget.resaleValue = max(0, entry.resaleValue)
            gadget.resaleRateToBase = max(0, entry.resaleRateToBase)
            gadget.createdAt = entry.createdAt
            context.insert(gadget)
            added += 1
        }
        return (added, skipped)
    }

    /// Name + price + purchase day is enough to recognise the same purchase twice.
    private static func identity(_ gadget: Gadget) -> String {
        "\(gadget.name.lowercased())|\(gadget.price)|\(gadget.purchaseDate.startOfDay.timeIntervalSince1970)"
    }

    private static func identity(_ entry: BackupFile.Entry) -> String {
        "\(entry.name.lowercased())|\(entry.price)|\(entry.purchaseDate.startOfDay.timeIntervalSince1970)"
    }
}
