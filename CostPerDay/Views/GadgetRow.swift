import SwiftUI

struct GadgetRow: View {
    let gadget: Gadget
    let mode: CostMode
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: gadget.category.symbol)
                .font(.title3)
                .foregroundStyle(gadget.category.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(gadget.name.isEmpty ? "Untitled" : gadget.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                LifetimeBar(progress: gadget.lifetimeProgress(), tint: gadget.category.tint)
                    .padding(.top, 2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.perDay(gadget.costPerDay(mode: mode), code: currency))
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .lineLimit(1)
                Text("per day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(gadget.isRetired ? 0.55 : 1)
    }

    /// Shows the price in the currency it was actually paid in — that's the number
    /// the user remembers — and only converts for the per-day figure.
    private var subtitle: String {
        var parts: [String] = [Money.string(gadget.price, code: gadget.currencyCode)]
        if gadget.isRetired {
            parts.append("retired after \(Duration.fromDays(gadget.daysOwned()))")
        } else if gadget.isPaidOff() {
            parts.append("paid off · \(Duration.fromDays(gadget.daysOwned())) owned")
        } else {
            parts.append("\(Duration.fromDays(gadget.daysOwned())) owned")
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
