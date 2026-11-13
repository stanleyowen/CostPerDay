import SwiftUI
import SwiftData

enum AppTab: String, Hashable {
    case home, transactions, reports, items, settings
}

/// App-wide navigation state, so a Shortcut, a widget-style deep link or a tap on a
/// report can say "show the composer" or "show these transactions" from anywhere.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()

    var tab: AppTab = .home
    /// Non-nil presents the transaction composer, prefilled with this.
    var composer: RecordDraft?
    /// An item just created from a purchase, to confirm in the item editor.
    var itemToConfirm: Item?
    var transactionFilter = TransactionFilter()
    /// Non-nil presents the editor for an existing transaction, from any screen.
    var recordToEdit: Record?
    /// The message of the Undo bar for the most recent list delete.
    var undoNotice: String?

    /// Deletes from a list in one undoable step and offers Undo (`View.undoBar()`).
    func delete(_ models: [any PersistentModel], named name: String, in context: ModelContext) {
        guard !models.isEmpty else { return }
        context.undoManager?.beginUndoGrouping()
        for model in models { context.delete(model) }
        context.undoManager?.endUndoGrouping()
        withAnimation {
            undoNotice = String(localized: "Deleted \(name)", comment: "Undo bar message. The placeholder is an item name or a count.")
        }
    }

    func undoDelete(in context: ModelContext) {
        context.undoManager?.undo()
        dismissUndo()
    }

    func dismissUndo() {
        withAnimation { undoNotice = nil }
    }

    func compose(_ kind: RecordKind = .expense) {
        composer = RecordDraft(kind: kind)
    }

    func showTransactions(_ filter: TransactionFilter) {
        transactionFilter = filter
        tab = .transactions
    }
}
