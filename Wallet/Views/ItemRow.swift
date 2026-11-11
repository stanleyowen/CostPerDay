import SwiftUI

struct ItemRow: View {
    let row: ItemRowModel
    let currency: String

    private var item: Item { row.item }

    var body: some View {
        HStack(spacing: 14) {
            ItemGlyph(category: row.category, progress: row.progress, isRetired: item.isRetired, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Money.perDay(row.costPerDay, code: currency))
                    .font(.system(.callout, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(item.isRetired ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .contentTransition(.numericText(value: row.costPerDay))
                    .lineLimit(1)
                if item.isRetired {
                    Text("Retired")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("per day")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(item.isRetired ? 0.7 : 1)
        .accessibilityElement(children: .combine)
    }

    /// Shows the price in the currency it was actually paid in — that is the figure
    /// the owner recognises — and only converts for the per-day amount.
    private var subtitle: String {
        let price = Money.string(item.price, code: item.currencyCode)
        let owned = Duration.fromDays(row.daysOwned)
        if item.isRetired {
            return String(
                localized: "\(price) · retired after \(owned)",
                comment: "Item row subtitle. First placeholder is a price, second a duration."
            )
        }
        if row.isPaidOff {
            return String(
                localized: "\(price) · fully amortised · \(owned) owned",
                comment: "Item row subtitle for an item past its expected lifetime."
            )
        }
        return String(
            localized: "\(price) · \(owned) owned",
            comment: "Item row subtitle. First placeholder is a price, second a duration."
        )
    }
}

/// The peek shown when long-pressing a row: both cost bases and lifetime at a glance.
struct ItemPreviewCard: View {
    let row: ItemRowModel
    let currency: String

    private var item: Item { row.item }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ItemGlyph(category: row.category, progress: row.progress, isRetired: item.isRetired, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName).font(.headline).lineLimit(1)
                    Text(row.category.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 0) {
                figure(CostMode.actual.label, item.actualCostPerDay())
                Divider().frame(height: 36)
                figure(CostMode.planned.label, item.plannedCostPerDay)
            }
            LifetimeBar(progress: row.progress, tint: row.category.tint, height: 6)
        }
        .padding(20)
        .frame(width: 320)
    }

    private func figure(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.perDay(value, code: currency))
                .font(.system(.title3, design: .rounded).weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}

/// Thin bar showing how far through its expected life an item is.
/// Fills with the category colour, then turns green once the item has outlived its budget.
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
                    .fill(clamped >= 1 ? Brand.paidOff : tint)
                    .frame(width: max(height, geo.size.width * clamped))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
