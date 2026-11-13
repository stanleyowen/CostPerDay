import SwiftUI

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
    /// The transaction editor, presented once at the root: a new transaction or an
    /// existing one. One sheet for both, so the editor can hand over to another
    /// (Duplicate opens a prefilled new one in its place).
    var recordSheet: RecordSheet?
    /// Non-nil presents the transaction composer, prefilled with this.
    var composer: RecordDraft? {
        get { if case .new(let draft) = recordSheet { draft } else { nil } }
        set { recordSheet = newValue.map(RecordSheet.new) }
    }
    /// Non-nil opens this transaction in the editor. Tapping a transaction anywhere
    /// does this (`RecordLink`); there's no separate read-only screen.
    var recordToEdit: Record? {
        get { if case .edit(let record) = recordSheet { record } else { nil } }
        set { recordSheet = newValue.map(RecordSheet.edit) }
    }
    /// An item just created from a purchase, to confirm in the item editor.
    var itemToConfirm: Item?
    var transactionFilter = TransactionFilter()
    /// A delete from a list row, waiting for the root view's confirmation alert.
    var pendingDelete: DeleteRequest?

    func compose(_ kind: RecordKind = .expense) {
        composer = RecordDraft(kind: kind)
    }

    func showTransactions(_ filter: TransactionFilter) {
        transactionFilter = filter
        tab = .transactions
    }
}

enum RecordSheet: Identifiable {
    case new(RecordDraft)
    case edit(Record)

    var id: String {
        switch self {
        case .new(let draft): "new|" + draft.id
        case .edit(let record): "edit|" + record.uuid.uuidString
        }
    }
}
