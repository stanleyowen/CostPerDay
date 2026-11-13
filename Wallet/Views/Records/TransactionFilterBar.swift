import SwiftUI

/// The filter fixed to the bottom of every transaction list (the Transactions tab
/// and each account's page). Three pages you swipe between, each a way to pick
/// the period:
///
/// 1. A rolling window: All time, 7 days, 30 days, 12 weeks, 6 months, 1 year.
/// 2. A calendar period you step through: ‹ This month ›, with a menu for day,
///    week, month or year.
/// 3. A custom range: from – to.
///
/// Pull it up (or tap the grabber) for the rest: which accounts, and more filters
/// (type, categories, labels, items). Whatever is selected is in the accent colour.
struct TransactionFilterBar: View {
    @Binding var filter: TransactionFilter
    /// The accounts to choose from; empty hides the Accounts row (an account's own
    /// page is already one account).
    var accounts: [Account] = []
    var labels: [String] = []

    /// Opens on the page of the period in force.
    @State private var page: Int
    // `-expandFilters` (and `-filterPage <n>` below): screenshot hooks, inert in Release.
    @State private var expanded = DebugFlags.has("-expandFilters")
    @State private var editing: TransactionFilterSheet.Part?
    /// Shown on the custom-range page before a range is chosen: the last week.
    @State private var rangeStart = Calendar.current.date(byAdding: .day, value: -6, to: .now.startOfDay) ?? .now
    @State private var rangeEnd = Date.now

    private static let pages = 3

    init(filter: Binding<TransactionFilter>, accounts: [Account] = [], labels: [String] = []) {
        _filter = filter
        self.accounts = accounts
        self.labels = labels
        let start = DebugFlags.value(after: "-filterPage").flatMap(Int.init) ?? Self.page(for: filter.wrappedValue.period)
        _page = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            TabView(selection: $page) {
                recentPage.tag(0)
                calendarPage.tag(1)
                customPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 44)

            PageIndicator(count: Self.pages, current: page) { index in
                withAnimation(.snappy) { page = index }
            }
            .padding(.top, 2)

            if expanded {
                VStack(spacing: 0) {
                    Divider().padding(.top, 6)
                    if !accounts.isEmpty {
                        row(String(localized: "Accounts"), value: accountsSummary) { editing = .accounts }
                        Divider().padding(.leading, 16)
                    }
                    row(String(localized: "More filters", comment: "Transaction filter sheet title"), value: detailsSummary) { editing = .details }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 6)
        .background(.bar, in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: -2)
        .sheet(item: $editing) { part in
            TransactionFilterSheet(filter: $filter, part: part, accounts: accounts, labels: labels)
                .presentationDetents(part == .accounts ? [.medium, .large] : [.large])
        }
        .sensoryFeedback(.selection, trigger: filter.period)
    }

    /// Which page shows the period in force.
    private static func page(for period: TransactionPeriod) -> Int {
        switch period {
        case .all, .recent: 0
        case .calendar: 1
        case .custom: 2
        }
    }

    // MARK: Grabber

    /// Tap or drag up for more filters; drag down to fold them away.
    private var grabber: some View {
        Capsule()
            .fill(.tertiary)
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .contentShape(.rect)
            .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
            .gesture(
                DragGesture(minimumDistance: 8).onEnded { value in
                    if value.translation.height < -12 { withAnimation(.snappy) { expanded = true } }
                    if value.translation.height > 12 { withAnimation(.snappy) { expanded = false } }
                }
            )
            .accessibilityElement()
            .accessibilityLabel(Text("More filters", comment: "Transaction filter sheet title"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { withAnimation(.snappy) { expanded.toggle() } }
    }

    // MARK: Pages

    private var recentPage: some View {
        let options: [TransactionPeriod] = [.all] + TransactionPeriod.RecentSpan.allCases.map(TransactionPeriod.recent)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(options, id: \.self) { option in
                    let selected = filter.period == option
                    Button {
                        withAnimation(.snappy) { filter.period = option }
                    } label: {
                        Text(option.label())
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selected ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.clear), in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Color(.tertiarySystemFill), in: .capsule)
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
    }

    private var calendarPage: some View {
        // Off this page's kind of period, it shows "This month" in grey; using it
        // switches to it.
        let active: Bool
        let shown: TransactionPeriod
        if case .calendar = filter.period {
            active = true
            shown = filter.period
        } else {
            active = false
            shown = .calendar(.month, offset: 0)
        }
        let atCurrent: Bool = { if case .calendar(_, 0) = shown { true } else { false } }()
        let foreground: AnyShapeStyle = active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)

        return HStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { filter.period = shown.stepped(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 38)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Previous period"))

            Menu {
                ForEach(TransactionPeriod.CalendarSpan.allCases, id: \.self) { span in
                    Button(span.currentLabel) {
                        withAnimation(.snappy) { filter.period = .calendar(span, offset: 0) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(shown.label())
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(active ? Color.black.opacity(0.18) : Color(.secondarySystemFill), in: .rect(cornerRadius: 12, style: .continuous))
                .contentShape(.rect)
            }

            Button {
                withAnimation(.snappy) { filter.period = shown.stepped(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 38)
                    .contentShape(.rect)
            }
            .disabled(atCurrent)
            .opacity(atCurrent ? 0.35 : 1)
            .accessibilityLabel(Text("Next period"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .padding(3)
        .background(active ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .rect(cornerRadius: 15, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var customPage: some View {
        let active: Bool
        let start: Date
        let end: Date
        if case .custom(let from, let to) = filter.period {
            active = true
            start = from
            end = to
        } else {
            active = false
            start = rangeStart
            end = rangeEnd
        }
        return HStack(spacing: 8) {
            DatePicker("From", selection: Binding(get: { start }, set: { setRange(start: $0, end: max($0, end)) }),
                       in: ...Date.now, displayedComponents: .date)
            Text(verbatim: "–")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            DatePicker("To", selection: Binding(get: { end }, set: { setRange(start: min(start, $0), end: $0) }),
                       in: ...Date.now, displayedComponents: .date)
        }
        .labelsHidden()
        .datePickerStyle(.compact)
        .frame(maxWidth: .infinity)
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(active ? AnyShapeStyle(Brand.accent) : AnyShapeStyle(.clear), lineWidth: 2)
        }
        .padding(.horizontal, 16)
    }

    private func setRange(start: Date, end: Date) {
        rangeStart = start
        rangeEnd = end
        withAnimation(.snappy) { filter.period = .custom(start: start, end: end) }
    }

    // MARK: Expanded rows

    private func row(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(value).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var accountsSummary: String {
        let chosen = accounts.filter { filter.accounts.contains($0.uuid) }
        switch chosen.count {
        case 0: return String(localized: "All accounts")
        case 1: return chosen[0].displayName
        default: return String(localized: "\(chosen.count) accounts", comment: "Home: the balance of several selected accounts")
        }
    }

    private var detailsSummary: String {
        filter.detailCount == 0
            ? String(localized: "None")
            : String(localized: "\(filter.detailCount) active", comment: "Transaction filter: number of extra filters in use")
    }
}

extension TransactionFilterSheet.Part: Identifiable {
    var id: Self { self }
}
