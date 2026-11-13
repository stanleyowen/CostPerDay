import SwiftUI

// MARK: - Cancel
//
// Every sheet's Cancel is red, and an editor with unsaved changes asks before
// throwing them away — with the same centred alert everywhere. Nothing changed,
// nothing asked: Cancel just closes.
//
// "Changed" is decided by each editor comparing its draft with a baseline taken
// once, after it has filled in its own defaults (an `Equatable` comparison of a
// few fields — no fetching, nothing recomputed on each keystroke beyond that).

/// The red Cancel. Use `View.cancelAction(hasChanges:perform:)` in editors; this
/// alone suits sheets that have nothing to lose.
struct CancelButton: View {
    let action: () -> Void

    var body: some View {
        Button("Cancel", action: action)
            .tint(.red)
    }
}

extension View {
    /// Puts the red Cancel in the toolbar. With `hasChanges`, Cancel asks first and
    /// swiping the sheet down is blocked, so edits can't be lost by accident.
    /// `blocksSwipe` also blocks it without changes, for a sheet that must clean up
    /// through `perform` (a new item already inserted, for instance).
    func cancelAction(hasChanges: Bool = false, blocksSwipe: Bool = false, perform: @escaping () -> Void) -> some View {
        modifier(CancelAction(hasChanges: hasChanges, blocksSwipe: blocksSwipe, perform: perform))
    }
}

private struct CancelAction: ViewModifier {
    let hasChanges: Bool
    let blocksSwipe: Bool
    let perform: () -> Void
    @State private var confirming = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CancelButton {
                        if hasChanges { confirming = true } else { perform() }
                    }
                }
            }
            .alert(Text("Discard unsaved changes?"), isPresented: $confirming) {
                Button("Discard Changes", role: .destructive, action: perform)
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("You have changes that haven't been saved. If you leave now, they'll be lost.")
            }
            .interactiveDismissDisabled(hasChanges || blocksSwipe)
    }
}
