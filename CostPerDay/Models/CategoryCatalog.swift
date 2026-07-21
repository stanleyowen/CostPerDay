import SwiftUI

/// Everything the UI needs to render one category, whether it's built in or user-defined.
struct CategoryDisplay: Identifiable, Hashable {
    let key: String
    let label: String
    let symbol: String
    let tint: Color
    let sector: Sector
    let defaultLifetimeMonths: Int
    let isCustom: Bool
    /// True when an item points at a category that no longer exists — a custom one
    /// the user deleted, or a built-in from a newer version of the app.
    let isMissing: Bool

    var id: String { key }
}

/// Resolves the category key stored on an item into something displayable, merging
/// the built-in list with whatever custom categories the user has defined.
///
/// Built as a value type from a `@Query` of custom categories, so views stay in sync
/// automatically when a custom category is added, renamed, or deleted.
struct CategoryCatalog {
    let customCategories: [CustomCategory]
    private let customByKey: [String: CustomCategory]

    init(custom: [CustomCategory] = []) {
        let sorted = custom.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.customCategories = sorted
        self.customByKey = Dictionary(sorted.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func display(for key: String) -> CategoryDisplay {
        if let builtIn = ItemCategory(rawValue: key) {
            return Self.display(for: builtIn)
        }
        if let custom = customByKey[key] {
            return Self.display(for: custom)
        }
        // The category was deleted out from under this item. Show it neutrally rather
        // than silently reassigning — the item's own cost data is still perfectly valid.
        return CategoryDisplay(
            key: key,
            label: String(localized: "Removed category", comment: "Shown when an item refers to a category that no longer exists"),
            symbol: "questionmark.circle",
            tint: .secondary,
            sector: .other,
            defaultLifetimeMonths: ItemCategory.other.defaultLifetimeMonths,
            isCustom: false,
            isMissing: true
        )
    }

    static func display(for category: ItemCategory) -> CategoryDisplay {
        CategoryDisplay(
            key: category.rawValue,
            label: category.label,
            symbol: category.symbol,
            tint: category.tint,
            sector: category.sector,
            defaultLifetimeMonths: category.defaultLifetimeMonths,
            isCustom: false,
            isMissing: false
        )
    }

    static func display(for custom: CustomCategory) -> CategoryDisplay {
        CategoryDisplay(
            key: custom.key,
            label: custom.name.isEmpty ? String(localized: "Untitled", comment: "Fallback name for an unnamed custom category") : custom.name,
            symbol: custom.symbolName,
            tint: custom.tint.color,
            sector: custom.sector,
            defaultLifetimeMonths: custom.defaultLifetimeMonths,
            isCustom: true,
            isMissing: false
        )
    }

    func customs(in sector: Sector) -> [CategoryDisplay] {
        customCategories.filter { $0.sector == sector }.map(Self.display(for:))
    }

    /// Built-ins followed by the user's own categories, for one sector.
    func categories(in sector: Sector) -> [CategoryDisplay] {
        ItemCategory.inSector(sector).map(Self.display(for:)) + customs(in: sector)
    }

    /// Every sector that has at least one category, in declaration order — the
    /// backbone of the grouped picker.
    var grouped: [(sector: Sector, categories: [CategoryDisplay])] {
        Sector.allCases.compactMap { sector in
            let categories = categories(in: sector)
            return categories.isEmpty ? nil : (sector, categories)
        }
    }
}
