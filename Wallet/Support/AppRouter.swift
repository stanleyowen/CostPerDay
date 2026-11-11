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
    /// Non-nil presents the transaction composer, prefilled with this.
    var composer: RecordDraft?
    /// An item just created from a purchase, to confirm in the item editor.
    var itemToConfirm: Item?
    var transactionFilter = TransactionFilter()

    func compose(_ kind: RecordKind = .expense) {
        composer = RecordDraft(kind: kind)
    }

    func showTransactions(_ filter: TransactionFilter) {
        transactionFilter = filter
        tab = .transactions
    }
}
