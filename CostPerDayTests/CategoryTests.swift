import Testing
import Foundation
import UIKit
@testable import CostPerDay

@Suite("Built-in categories")
struct ItemCategoryTests {
    @Test("Every category renders a real SF Symbol")
    func everySymbolResolves() {
        for category in ItemCategory.allCases {
            #expect(
                UIImage(systemName: category.symbol) != nil,
                "\(category.rawValue) uses a symbol that doesn't exist: \(category.symbol)"
            )
        }
    }

    @Test("Every sector renders a real SF Symbol")
    func everySectorSymbolResolves() {
        for sector in Sector.allCases {
            #expect(
                UIImage(systemName: sector.symbol) != nil,
                "\(sector.rawValue) uses a symbol that doesn't exist: \(sector.symbol)"
            )
        }
    }

    @Test("Every symbol offered for custom categories is real")
    func everyPickableSymbolResolves() {
        for symbol in CategorySymbols.choices {
            #expect(UIImage(systemName: symbol) != nil, "custom-category symbol missing: \(symbol)")
        }
    }

    @Test("Every sector has at least one built-in category")
    func everySectorIsPopulated() {
        for sector in Sector.allCases {
            #expect(!ItemCategory.inSector(sector).isEmpty, "\(sector.rawValue) has no categories")
        }
    }

    @Test("Sector assignment partitions the categories exactly once")
    func sectorsPartitionAllCategories() {
        let regrouped = Sector.allCases.flatMap { ItemCategory.inSector($0) }
        #expect(regrouped.count == ItemCategory.allCases.count)
        #expect(Set(regrouped) == Set(ItemCategory.allCases))
    }

    @Test("Every category has a usable default lifetime")
    func lifetimesAreSane() {
        for category in ItemCategory.allCases {
            #expect(category.defaultLifetimeMonths >= 1)
            #expect(category.defaultLifetimeMonths <= Item.maxLifetimeMonths)
        }
    }

    @Test("The electronics categories kept their original raw values")
    func legacyRawValuesArePreserved() {
        // Renaming any of these would orphan items saved by earlier versions.
        let legacy = ["phone", "laptop", "tablet", "desktop", "monitor", "audio",
                      "wearable", "camera", "gaming", "accessory", "smartHome", "other"]
        for raw in legacy {
            #expect(ItemCategory(rawValue: raw) != nil, "lost the '\(raw)' category")
        }
    }
}

@Suite("Category catalog")
struct CategoryCatalogTests {
    private func custom(_ name: String, sector: Sector = .home) -> CustomCategory {
        CustomCategory(name: name, symbolName: "star", sector: sector, tint: .purple, defaultLifetimeMonths: 42)
    }

    @Test("A built-in key resolves to that category")
    func resolvesBuiltIn() {
        let display = CategoryCatalog().display(for: ItemCategory.seating.rawValue)
        #expect(display.label == "Sofa & Seating")
        #expect(display.sector == .home)
        #expect(!display.isCustom)
        #expect(!display.isMissing)
    }

    @Test("A custom key resolves to the user's category")
    func resolvesCustom() {
        let mine = custom("Plants", sector: .home)
        let display = CategoryCatalog(custom: [mine]).display(for: mine.key)
        #expect(display.label == "Plants")
        #expect(display.defaultLifetimeMonths == 42)
        #expect(display.isCustom)
        #expect(!display.isMissing)
    }

    @Test("A key with no matching category is flagged rather than silently remapped")
    func unknownKeyIsFlagged() {
        let display = CategoryCatalog().display(for: "custom:\(UUID().uuidString)")
        #expect(display.isMissing)
        #expect(display.sector == .other)
    }

    @Test("Custom keys can never collide with a built-in raw value")
    func customKeysAreNamespaced() {
        let mine = custom("Phone")
        #expect(mine.key.hasPrefix(CustomCategory.keyPrefix))
        #expect(ItemCategory(rawValue: mine.key) == nil)
    }

    @Test("A custom key round-trips back to its UUID")
    func keyRoundTripsToUUID() {
        let mine = custom("Plants")
        #expect(CustomCategory.uuid(fromKey: mine.key) == mine.uuid)
        #expect(CustomCategory.uuid(fromKey: "phone") == nil)
    }

    @Test("Custom categories appear in their own sector's group")
    func customsJoinTheirSector() {
        let catalog = CategoryCatalog(custom: [custom("Plants", sector: .home)])
        let homeKeys = catalog.categories(in: .home).map(\.label)
        #expect(homeKeys.contains("Plants"))
        #expect(!catalog.categories(in: .active).contains { $0.label == "Plants" })
    }

    @Test("Grouping covers every category exactly once")
    func groupingIsComplete() {
        let catalog = CategoryCatalog(custom: [custom("Plants"), custom("Pets", sector: .other)])
        let grouped = catalog.grouped.flatMap(\.categories)
        #expect(grouped.count == ItemCategory.allCases.count + 2)
        #expect(Set(grouped.map(\.key)).count == grouped.count)
    }

    @Test("An empty custom name still shows something readable")
    func blankCustomNameFallsBack() {
        let display = CategoryCatalog.display(for: custom(""))
        #expect(display.label == "Untitled")
    }
}

@Suite("Custom categories in backups")
struct CustomCategoryBackupTests {
    @Test("Custom categories survive an export/import round trip")
    func customCategoriesRoundTrip() throws {
        let mine = CustomCategory(name: "Plants", symbolName: "leaf", sector: .home, tint: .green, defaultLifetimeMonths: 24)
        let item = Item(name: "Fiddle Leaf Fig", price: 80)
        item.categoryKey = mine.key

        let file = Backup.makeFile(gadgets: [item], baseCurrency: "USD", customCategories: [mine])
        let decoded = try Backup.decode(try Backup.encode(file))

        let categories = try #require(decoded.customCategories)
        #expect(categories.count == 1)
        #expect(categories[0].name == "Plants")
        #expect(categories[0].uuid == mine.uuid)
        #expect(categories[0].tint == CategoryTint.green.rawValue)
        // The item still points at the category by the same key.
        #expect(decoded.gadgets[0].category == mine.key)
    }

    @Test("A v1 backup with no custom categories still decodes")
    func version1FileStillDecodes() throws {
        let legacy = """
        {
          "formatVersion": 1,
          "exportedAt": "2025-06-15T00:00:00Z",
          "baseCurrency": "USD",
          "gadgets": [{
            "name": "iPhone", "brand": "Apple", "category": "phone", "price": 999,
            "currencyCode": "USD", "rateToBase": 1,
            "purchaseDate": "2024-01-01T00:00:00Z", "expectedLifetimeMonths": 36,
            "notes": "", "resaleValue": 0, "resaleRateToBase": 0,
            "createdAt": "2024-01-01T00:00:00Z"
          }]
        }
        """
        let decoded = try Backup.decode(Data(legacy.utf8))
        #expect(decoded.formatVersion == 1)
        #expect(decoded.customCategories == nil)
        #expect(decoded.gadgets.count == 1)
    }
}
