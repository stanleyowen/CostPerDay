import SwiftUI

struct ItemRow: View {
    let item: Item
    let category: CategoryDisplay
    let mode: CostMode
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.title3)
                .foregroundStyle(category.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name.isEmpty ? "Untitled" : item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                LifetimeBar(progress: item.lifetimeProgress(), tint: category.tint)
                    .padding(.top, 2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.perDay(item.costPerDay(mode: mode), code: currency))
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .lineLimit(1)
                Text("per day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(item.isRetired ? 0.55 : 1)
    }

    /// Shows the price in the currency it was actually paid in — that's the number
    /// the user remembers — and only converts for the per-day figure.
    private var subtitle: String {
        var parts: [String] = [Money.string(item.price, code: item.currencyCode)]
        if item.isRetired {
            parts.append("retired after \(Duration.fromDays(item.daysOwned()))")
        } else if item.isPaidOff() {
            parts.append("paid off · \(Duration.fromDays(item.daysOwned())) owned")
        } else {
            parts.append("\(Duration.fromDays(item.daysOwned())) owned")
        }
        return parts.joined(separator: " · ")
    }
}

/// Thin bar showing how far through its expected life an item is.
/// Fills to the accent colour, then turns green once the item has outlived its budget.
struct LifetimeBar: View {
    let progress: Double
    var tint: Color = .accentColor
    var height: CGFloat = 4

    private var clamped: Double {
        progress.isFinite ? min(1, max(0, progress)) : 0
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(clamped >= 1 ? Color.green : tint)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: height)
    }
}
