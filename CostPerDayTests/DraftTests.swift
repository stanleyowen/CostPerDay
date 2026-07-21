import Testing
import Foundation
@testable import CostPerDay

/// Covers the bug where editing an existing item and tapping Cancel still saved the
/// changes — because the edit form bound directly to the live SwiftData object, and
/// SwiftData's autosave could persist an in-progress edit before Cancel ever ran.
/// The fix routes all editing through an unmanaged `ItemDraft`/`CustomCategoryDraft`
/// that is only ever written back with an explicit `apply(to:)` call. These tests
/// pin that isolation down directly, independent of SwiftUI or autosave timing.
@Suite("Draft editing")
struct DraftTests {
    private func item() -> Item {
        Item(name: "Original", price: 100, purchaseDate: Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Mutating a draft never touches the source item")
    func draftIsIsolatedFromSource() {
        let original = item()
        var draft = ItemDraft(item: original)

        draft.name = "Edited"
        draft.price = 999
        draft.notes = "changed my mind"
        draft.expectedLifetimeMonths = 12

        #expect(original.name == "Original")
        #expect(original.price == 100)
        #expect(original.notes == "")
        #expect(original.expectedLifetimeMonths == 36)
    }

    @Test("Discarding a draft — never calling apply — leaves the item exactly as it was")
    func neverApplyingLeavesItemUnchanged() {
        let original = item()
        var draft = ItemDraft(item: original)
        draft.name = "Edited"
        draft.price = 999
        draft.currencyCode = "JPY"
        draft.resaleValue = 50
        // Simulates pressing Cancel: draft is simply dropped.
        _ = draft

        #expect(original.name == "Original")
        #expect(original.price == 100)
        #expect(original.currencyCode != "JPY")
        #expect(original.resaleValue == 0)
    }

    @Test("Applying a draft writes every editable field back to the item")
    func applyWritesAllFields() {
        let original = item()
        var draft = ItemDraft(item: original)
        draft.name = "Edited"
        draft.brand = "Acme"
        draft.categoryKey = ItemCategory.laptop.rawValue
        draft.price = 250
        draft.currencyCode = "EUR"
        draft.rateToBase = 1.1
        draft.expectedLifetimeMonths = 48
        draft.notes = "gift"
        draft.resaleValue = 30
        draft.resaleRateToBase = 1.05

        draft.apply(to: original)

        #expect(original.name == "Edited")
        #expect(original.brand == "Acme")
        #expect(original.categoryKey == ItemCategory.laptop.rawValue)
        #expect(original.price == 250)
        #expect(original.currencyCode == "EUR")
        #expect(original.rateToBase == 1.1)
        #expect(original.expectedLifetimeMonths == 48)
        #expect(original.notes == "gift")
        #expect(original.resaleValue == 30)
        #expect(original.resaleRateToBase == 1.05)
    }

    @Test("Apply does not touch fields the draft doesn't own, like retiredDate")
    func applyLeavesUneditedFieldsAlone() {
        let original = item()
        original.retiredDate = Date(timeIntervalSince1970: 1_750_000_000)
        let draft = ItemDraft(item: original)

        draft.apply(to: original)

        #expect(original.retiredDate == Date(timeIntervalSince1970: 1_750_000_000))
    }

    @Test("A draft's cost math matches the equivalent live item exactly")
    func draftCostMathMatchesItem() {
        let original = Item(
            name: "Camera", price: 1500, currencyCode: "USD", rateToBase: 1,
            purchaseDate: Date(timeIntervalSince1970: 1_650_000_000),
            expectedLifetimeMonths: 60
        )
        let draft = ItemDraft(item: original)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(draft.actualCostPerDay(now: now) == original.actualCostPerDay(now: now))
        #expect(draft.plannedCostPerDay == original.plannedCostPerDay)
        #expect(draft.daysOwned(now: now) == original.daysOwned(now: now))
        #expect(draft.netCost == original.netCost)
    }

    @Test("Validation runs identically against a draft and against the item it came from")
    func validationAgreesOnDraftAndItem() {
        let original = item()
        original.price = 0 // invalid
        let draft = ItemDraft(item: original)

        let itemIssues = Set(ItemValidation.issues(for: original, baseCurrency: "USD").map(\.field))
        let draftIssues = Set(ItemValidation.issues(for: draft, baseCurrency: "USD").map(\.field))
        #expect(itemIssues == draftIssues)
        #expect(itemIssues.contains(.price))
    }

    // MARK: Custom category draft

    private func customCategory() -> CustomCategory {
        CustomCategory(name: "Plants", symbolName: "leaf", sector: .home, tint: .green, defaultLifetimeMonths: 24)
    }

    @Test("Mutating a custom-category draft never touches the source category")
    func customCategoryDraftIsIsolated() {
        let original = customCategory()
        var draft = CustomCategoryDraft(category: original)

        draft.name = "Renamed"
        draft.symbolName = "star"
        draft.sector = .active
        draft.tint = .red
        draft.defaultLifetimeMonths = 99

        #expect(original.name == "Plants")
        #expect(original.symbolName == "leaf")
        #expect(original.sector == .home)
        #expect(original.tint == .green)
        #expect(original.defaultLifetimeMonths == 24)
    }

    @Test("Applying a custom-category draft writes every field back")
    func customCategoryApplyWritesAllFields() {
        let original = customCategory()
        var draft = CustomCategoryDraft(category: original)
        draft.name = "Renamed"
        draft.symbolName = "star"
        draft.sector = .active
        draft.tint = .red
        draft.defaultLifetimeMonths = 99

        draft.apply(to: original)

        #expect(original.name == "Renamed")
        #expect(original.symbolName == "star")
        #expect(original.sector == .active)
        #expect(original.tint == .red)
        #expect(original.defaultLifetimeMonths == 99)
    }
}
