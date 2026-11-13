import SwiftUI

// MARK: - Period stepper
//
// The one period control in the app: ‹ title ›, on Reports, the Transactions tab
// and every account's page. The arrows (or a sideways swipe) step to the previous
// or next period; the title is the caller's — Reports jumps back to now when it's
// tapped, transaction lists open a menu of periods.

struct PeriodStepper<Title: View>: View {
    /// False for a period with nothing to step through (all time, a rolling
    /// window): the arrows are hidden rather than shown disabled, keeping their
    /// room so the title doesn't move.
    var steppable = true
    let canGoBack: Bool
    let canGoForward: Bool
    let onStep: (Int) -> Void
    @ViewBuilder let title: Title

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", label: Text("Previous period"), enabled: canGoBack) { onStep(-1) }
                .opacity(steppable ? 1 : 0)
                .accessibilityHidden(!steppable)
            Spacer(minLength: 4)
            title
            Spacer(minLength: 4)
            arrow("chevron.right", label: Text("Next period"), enabled: canGoForward) { onStep(1) }
                .opacity(steppable ? 1 : 0)
                .accessibilityHidden(!steppable)
        }
        .animation(.snappy, value: steppable)
        .frame(minHeight: 44)
        .background(Color(.secondarySystemGroupedBackground), in: .capsule)
        .contentShape(.capsule)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0, canGoForward { onStep(1) }
                if value.translation.width > 0, canGoBack { onStep(-1) }
            }
        )
    }

    private func arrow(_ symbol: String, label: Text, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.quaternary))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The period control for a transaction list: ‹ This month › steps through
/// calendar periods; the title opens every other choice — a different calendar
/// unit, a rolling window ending today, all time, or a custom range.
struct TransactionPeriodControl: View {
    @Binding var period: TransactionPeriod
    @State private var choosingRange = false

    var body: some View {
        let steppable: Bool = { if case .calendar = period { true } else { false } }()
        let atCurrent: Bool = { if case .calendar(_, 0) = period { true } else { false } }()

        PeriodStepper(steppable: steppable, canGoBack: steppable, canGoForward: steppable && !atCurrent, onStep: step) {
            Menu {
                Picker("Period", selection: $period.animation(.snappy)) {
                    ForEach(TransactionPeriod.CalendarSpan.allCases, id: \.self) { span in
                        Text(span.currentLabel).tag(TransactionPeriod.calendar(span, offset: 0))
                    }
                }
                .pickerStyle(.inline)
                Picker("Period", selection: $period.animation(.snappy)) {
                    ForEach([TransactionPeriod.all] + TransactionPeriod.RecentSpan.allCases.map(TransactionPeriod.recent), id: \.self) { option in
                        Text(option.label()).tag(option)
                    }
                }
                .pickerStyle(.inline)
                Button {
                    choosingRange = true
                } label: {
                    Label(String(localized: "Custom range…", comment: "Period menu item"), systemImage: "calendar")
                }
            } label: {
                HStack(spacing: 5) {
                    Text(period.label())
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .contentShape(.rect)
            }
            // Black like every period title; the ▾ says it opens a menu.
            .tint(.primary)
            .accessibilityHint(Text("Choose a period", comment: "Accessibility hint on the period menu"))
        }
        .sensoryFeedback(.selection, trigger: period)
        .sheet(isPresented: $choosingRange) {
            CustomRangeSheet(period: $period)
                .presentationDetents([.medium])
        }
    }

    private func step(_ delta: Int) {
        withAnimation(.snappy) { period = period.stepped(by: delta) }
    }
}

/// From and to dates for a custom period; applied on Done.
private struct CustomRangeSheet: View {
    @Binding var period: TransactionPeriod
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date

    init(period: Binding<TransactionPeriod>) {
        _period = period
        // Starts from the period in force, or the last week.
        let shown = period.wrappedValue.interval() ?? TransactionPeriod.recent(.days7).interval()!
        _start = State(initialValue: shown.start)
        _end = State(initialValue: min(shown.end.addingTimeInterval(-1), .now))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $start, in: ...end, displayedComponents: .date)
                DatePicker("To", selection: $end, in: start...Date.now, displayedComponents: .date)
            }
            .navigationTitle(String(localized: "Custom range", comment: "Period filter"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { CancelButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        withAnimation(.snappy) { period = .custom(start: start, end: end) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

extension View {
    /// Pins a control under the navigation bar while the content scrolls beneath
    /// it — on iOS 26 as part of the bar's own glass edge, earlier on the screen's
    /// background.
    @ViewBuilder
    func pinnedHeader<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26, *) {
            safeAreaBar(edge: .top) {
                content().padding(.horizontal, 16).padding(.bottom, 6)
            }
        } else {
            safeAreaInset(edge: .top, spacing: 0) {
                content()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color(.systemGroupedBackground))
            }
        }
    }
}
