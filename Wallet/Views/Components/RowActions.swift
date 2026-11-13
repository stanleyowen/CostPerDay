import SwiftUI
import SwiftData

// MARK: - Row actions
//
// One set of rules for every list row that stands for something the user owns
// (a transaction, item, account, budget or custom category), so the same gesture
// does the same thing on every screen:
//
// - Swipe left: Delete (red), then Edit (accent).
// - Swipe right: the one action specific to that kind of row, if it has one —
//   Duplicate a transaction, Retire an item, Archive an account.
// - Long press: a menu with the same actions — Edit, the specific ones, Delete.
// - Delete in a list is instant and comes with an Undo bar (`View.undoBar()`). The
//   exception is an account, whose delete takes its transactions with it, so it
//   asks first with a centred alert. Delete buttons on detail screens and editors
//   also confirm with a centred alert, never an action sheet.
//
// Rows outside a `List` (the cards on Home and Reports) can't swipe, so they get
// the long-press menu only.

/// The tint for Edit in swipes, beside Delete's red.
let editActionTint = Brand.accent

extension View {
    /// The standard actions on a transaction row.
    func recordActions(_ record: Record) -> some View {
        modifier(RecordActions(record: record))
    }

    /// Shows the Undo bar for the most recent list delete at the bottom of the screen.
    func undoBar() -> some View {
        modifier(UndoBarInset())
    }
}

private struct RecordActions: ViewModifier {
    let record: Record
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { delete() } label: { Label("Delete", systemImage: "trash") }
                Button { router.recordToEdit = record } label: { Label("Edit", systemImage: "pencil") }
                    .tint(editActionTint)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { duplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .tint(editActionTint)
            }
            .contextMenu {
                Button("Edit", systemImage: "pencil") { router.recordToEdit = record }
                Button("Duplicate", systemImage: "plus.square.on.square") { duplicate() }
                if record.item == nil && record.kind == .expense {
                    Button("Track as item", systemImage: "shippingbox") {
                        router.itemToConfirm = LedgerActions.trackAsItem(record, in: context)
                    }
                }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { delete() }
            }
    }

    /// The composer, prefilled with this transaction, dated now.
    private func duplicate() {
        var copy = RecordDraft(record: record)
        copy.date = .now
        router.composer = copy
    }

    private func delete() {
        let name = record.note.isEmpty ? (record.category?.label ?? record.kind.label) : record.note
        router.delete([record], named: name, in: context)
    }
}

private struct UndoBarInset: ViewModifier {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if let notice = router.undoNotice {
                UndoBar(message: notice) { router.undoDelete(in: context) } dismiss: { router.dismissUndo() }
            }
        }
    }
}
