import SwiftUI

// MARK: - Transaction row

/// One line in any transaction list: category tile, what it was, where, how much.
struct RecordRow: View {
    let flow: Flow
    let accountLine: String
    var showsDate = false
    var linkedItemName: String?

    var body: some View {
        let category = flow.category
        HStack(spacing: 12) {
            CategoryTile(symbol: category.symbol, tint: category.tint, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title(category))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let linkedItemName {
                        Image(systemName: "shippingbox.fill")
                            .font(.caption2)
                            .foregroundStyle(Brand.accent)
                            .accessibilityLabel(Text("Tracked as \(linkedItemName)"))
                    }
                    Text(subtitle(category))
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !flow.labels.isEmpty {
                    LabelChips(labels: flow.labels, compact: true)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.signed(flow.safeAmount, code: flow.currencyCode, kind: flow.kind))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(amountStyle)
                    .lineLimit(1)
                if showsDate {
                    Text(flow.date.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(flow.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var amountStyle: AnyShapeStyle {
        switch flow.kind {
        case .income: AnyShapeStyle(Color.income)
        case .expense: AnyShapeStyle(.primary)
        case .transfer: AnyShapeStyle(.secondary)
        }
    }

    private func title(_ category: RecordCategoryDisplay) -> String {
        let note = flow.note.split(separator: "\n").first.map(String.init) ?? ""
        if !note.isEmpty { return note }
        if !flow.payee.isEmpty { return flow.payee }
        return category.label
    }

    private func subtitle(_ category: RecordCategoryDisplay) -> String {
        let hasNote = !flow.note.isEmpty || !flow.payee.isEmpty
        if flow.kind == .transfer { return accountLine }
        return hasNote ? "\(category.label) · \(accountLine)" : accountLine
    }
}

/// Small rounded label tags.
struct LabelChips: View {
    let labels: [String]
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(labels.prefix(compact ? 3 : 20), id: \.self) { label in
                Text(label)
                    .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
                    .padding(.horizontal, compact ? 6 : 8)
                    .padding(.vertical, compact ? 1.5 : 3)
                    .foregroundStyle(LabelTint.color(for: label))
                    .background(LabelTint.color(for: label).opacity(0.13), in: .capsule)
                    .lineLimit(1)
            }
            if compact && labels.count > 3 {
                Text(verbatim: "+\(labels.count - 3)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Labels get a stable colour derived from their text, so "Family Mart" is always
/// the same teal everywhere without the user having to pick one.
enum LabelTint {
    private static let palette: [Color] = [.blue, .teal, .purple, .pink, .orange, .indigo, .green, .cyan, .brown, .mint]

    static func color(for label: String) -> Color {
        // FNV-1a: stable across launches, unlike `hashValue`.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in label.lowercased().utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}

// MARK: - Accounts

/// A compact card for the accounts carousel: tinted, with the live balance.
struct AccountCard: View {
    let account: Account
    let balance: Double
    /// `nil` fills the width it's offered.
    var width: CGFloat? = 160
    /// A shorter card (icon and name on one line) for the paged grid on Home.
    var compact = false

    static let compactHeight: CGFloat = 84

    var body: some View {
        let tint = account.tint.color
        let height = compact ? Self.compactHeight : 118
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 8) {
                Image(systemName: account.kind.symbol)
                    .font((compact ? Font.caption : .subheadline).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: compact ? 26 : 30, height: compact ? 26 : 30)
                    .background(.white.opacity(0.2), in: .rect(cornerRadius: compact ? 8 : 9, style: .continuous))
                if compact { name }
                Spacer(minLength: 0)
                if account.excludeFromStats {
                    Image(systemName: "eye.slash")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            if !compact { name }
            Text(Money.exact(balance, code: account.currencyCode))
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                // Long amounts (NT$1,234,567.89) shrink to fit rather than truncate.
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(value: balance))
        }
        .padding(compact ? 12 : 14)
        .frame(width: width, height: height, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .background {
            LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(0.10))
                        .frame(width: compact ? 96 : 120)
                        .offset(x: compact ? 34 : 47, y: compact ? -46 : -51)
                }
        }
        .clipShape(.rect(cornerRadius: compact ? 18 : 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var name: some View {
        Text(account.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(1)
    }
}

// MARK: - Controls

/// Expense / Income / Transfer, as the standard iOS segmented control.
struct KindPicker: View {
    @Binding var kind: RecordKind
    var allowsTransfer = true

    var body: some View {
        Picker("Type", selection: $kind.animation(.snappy(duration: 0.25))) {
            ForEach(RecordKind.allCases.filter { allowsTransfer || $0 != .transfer }) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .sensoryFeedback(.selection, trigger: kind)
    }
}

extension RecordKind {
    var tint: Color {
        switch self {
        case .expense: Brand.expense
        case .income: .income
        case .transfer: RecordCategoryDisplay.transfer.tint
        }
    }
}

/// The round "+" that floats over the ledger screens, Wallet-style.
struct FloatingAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Brand.gradient, in: .circle)
                .shadow(color: Brand.accent.opacity(0.45), radius: 14, y: 6)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text("Add transaction"))
        .padding(.trailing, 20)
        .padding(.bottom, 12)
    }
}

/// Springy press feedback for prominent buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

/// A figure with a caption — used in summary strips.
struct FigureColumn: View {
    let title: String
    let value: String
    var tint: Color = .primary
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "▲ 12%" / "▼ 8%" against the previous period. For spending, up is bad.
struct ChangeBadge: View {
    let change: Double
    var upIsGood = false

    var body: some View {
        let up = change >= 0
        let good = up == upIsGood
        Label {
            Text(abs(change).formatted(.percent.precision(.fractionLength(0))))
        } icon: {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(good ? Color.income : Brand.expense)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((good ? Color.income : Brand.expense).opacity(0.13), in: .capsule)
    }
}
