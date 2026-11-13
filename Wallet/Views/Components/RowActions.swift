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
// - Delete is always red and always asks first, with the same centred alert
//   (`DeleteRequest`), wherever it starts: a swipe, a menu, a detail screen or
//   an editor. Never an action sheet, never an instant delete.
//
// Rows outside a `List` (the cards on Home and Reports) can't swipe, so they get
// the long-press menu only.

/// The tint for Edit in swipes, beside Delete's red.
let editActionTint = Brand.accent

/// A delete waiting for the user to confirm it: what the alert says and what
/// happens on Delete. Built by the factories below so every kind of thing gets
/// the same wording everywhere it can be deleted from.
struct DeleteRequest: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let perform: () -> Void
}

@MainActor
extension DeleteRequest {
    static func record(_ record: Record, in context: ModelContext, then done: @escaping () -> Void = {}) -> DeleteRequest {
        DeleteRequest(
            title: String(localized: "Delete this transaction?"),
            message: String(localized: "Account balances and reports will update. A tracked item linked to it is kept.")
        ) {
            context.delete(record)
            try? context.save()
            done()
        }
    }

    static func item(_ item: Item, in context: ModelContext, then done: @escaping () -> Void = {}) -> DeleteRequest {
        let name = item.name.isEmpty ? String(localized: "this item", comment: "Used in a delete confirmation when the item has no name") : item.name
        return DeleteRequest(
            title: String(localized: "Delete \(name)?"),
            message: String(localized: "This permanently removes the item from your history and statistics. If you have simply stopped using it, retire it instead.")
        ) {
            context.delete(item)
            try? context.save()
            done()
        }
    }

    /// Deleting an account takes its income and expenses with it (`LedgerActions.delete`).
    static func account(_ account: Account, in context: ModelContext, then done: @escaping () -> Void = {}) -> DeleteRequest {
        DeleteRequest(
            title: String(localized: "Delete \(account.displayName)?"),
            message: LedgerActions.deleteWarning(deleting: LedgerActions.recordsDeleted(with: account, in: context))
        ) {
            LedgerActions.delete(account, in: context)
            done()
        }
    }

    static func budget(_ budget: Budget, in context: ModelContext, then done: @escaping () -> Void = {}) -> DeleteRequest {
        DeleteRequest(
            title: String(localized: "Delete this budget?"),
            message: String(localized: "Your transactions aren't affected. This can't be undone.")
        ) {
            context.delete(budget)
            try? context.save()
            done()
        }
    }

    static func category(_ category: CustomCategory, in context: ModelContext, then done: @escaping () -> Void = {}) -> DeleteRequest {
        let name = category.name.isEmpty ? String(localized: "Untitled") : category.name
        return DeleteRequest(
            title: String(localized: "Delete \(name)?"),
            message: String(localized: "Items in this category keep it, marked as missing, until you choose another. This can't be undone.", comment: "Delete custom category alert message")
        ) {
            context.delete(category)
            try? context.save()
            done()
        }
    }
}

extension View {
    /// The standard actions on a transaction row.
    func recordActions(_ record: Record) -> some View {
        modifier(RecordActions(record: record))
    }

    /// Presents a pending delete as the standard centred alert: Cancel and a red
    /// Delete. The root view shows `router.pendingDelete`; sheets and detail screens
    /// that need to dismiss afterwards keep their own request.
    func deleteConfirmation(_ request: Binding<DeleteRequest?>) -> some View {
        alert(
            request.wrappedValue?.title ?? "",
            isPresented: Binding(get: { request.wrappedValue != nil }, set: { if !$0 { request.wrappedValue = nil } }),
            presenting: request.wrappedValue
        ) { pending in
            Button("Delete", role: .destructive) { withAnimation { pending.perform() } }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }
}

/// The red Delete for a swipe. Tinted rather than `role: .destructive`, which
/// would start animating the row away before the confirmation is answered.
struct SwipeDeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label("Delete", systemImage: "trash") }
            .tint(.red)
    }
}

/// The swipe Edit, in the accent colour.
struct SwipeEditButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label("Edit", systemImage: "pencil") }
            .tint(editActionTint)
    }
}

private struct RecordActions: ViewModifier {
    let record: Record
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                SwipeDeleteButton { delete() }
                SwipeEditButton { router.recordToEdit = record }
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
        router.pendingDelete = .record(record, in: context)
    }
}
