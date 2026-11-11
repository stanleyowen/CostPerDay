import Foundation

/// An unmanaged, in-memory copy of a custom category's editable fields — the
/// category-editing counterpart to `ItemDraft`, and for the same reason: the edit
/// form must never mutate the live `CustomCategory` until Save is pressed, or Cancel
/// can't reliably discard anything SwiftData's autosave already persisted.
struct CustomCategoryDraft {
    var name: String
    var symbolName: String
    var sector: Sector
    var tint: CategoryTint
    var defaultLifetimeMonths: Int

    init(category: CustomCategory) {
        name = category.name
        symbolName = category.symbolName
        sector = category.sector
        tint = category.tint
        defaultLifetimeMonths = category.defaultLifetimeMonths
    }

    /// Writes every editable field back onto the live category. Called only on Save.
    func apply(to category: CustomCategory) {
        category.name = name
        category.symbolName = symbolName
        category.sector = sector
        category.tint = tint
        category.defaultLifetimeMonths = defaultLifetimeMonths
    }
}
