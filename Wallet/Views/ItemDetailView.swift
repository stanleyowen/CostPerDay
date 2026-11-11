import SwiftUI
import SwiftData
import Charts

struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var customCategories: [CustomCategory]
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @AppStorage("costMode") private var costModeRaw = CostMode.actual.rawValue

    @State private var isEditing = false
    @State private var confirmingDelete = false
    @State private var linkingRecord = false

    private var isForeign: Bool { item.currencyCode != baseCurrency }
    private var costMode: CostMode { CostMode(rawValue: costModeRaw) ?? .actual }

    var body: some View {
        let category = CategoryCatalog(custom: customCategories).display(for: item.categoryKey)
        let now = Date.now
        let daysOwned = item.daysOwned(now: now)
        let progress = Double(daysOwned) / Double(item.plannedDays)

        ScrollView {
            VStack(spacing: 16) {
                header(category: category, progress: progress, now: now)

                HStack(spacing: 12) {
                    CostFigure(
                        title: CostMode.actual.label,
                        value: item.netCost / Double(daysOwned),
                        caption: String(localized: "over \(Duration.fromDays(daysOwned))", comment: "Caption under a cost figure. The placeholder is a duration."),
                        currency: baseCurrency,
                        isHighlighted: costMode == .actual
                    ) { costModeRaw = CostMode.actual.rawValue }
                    CostFigure(
                        title: CostMode.planned.label,
                        value: item.plannedCostPerDay,
                        caption: String(localized: "over \(Duration.fromMonths(item.expectedLifetimeMonths))", comment: "Caption under a cost figure. The placeholder is a duration."),
                        currency: baseCurrency,
                        isHighlighted: costMode == .planned
                    ) { costModeRaw = CostMode.planned.rawValue }
                }
                .sensoryFeedback(.selection, trigger: costModeRaw)

                CostCurveCard(item: item, daysOwned: daysOwned, tint: category.isMissing ? .secondary : category.tint, currency: baseCurrency)

                lifetimeCard(category: category, daysOwned: daysOwned, progress: progress)
                purchaseCard(category: category)
                ItemSpendingCard(item: item, daysOwned: daysOwned, currency: baseCurrency) { linkingRecord = true }

                if !item.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        CardHeader(title: String(localized: "Notes"))
                        Text(item.notes)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .card()
                }

                actions
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            ItemEditView(item: item, isNew: false)
        }
        .sheet(isPresented: $linkingRecord) {
            LinkRecordSheet(item: item)
        }
        .confirmationDialog(
            Text("Delete \(item.name.isEmpty ? String(localized: "this item", comment: "Used in a delete confirmation when the item has no name") : item.name)?"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                context.delete(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the item from your history and statistics. If you have simply stopped using it, retire it instead.")
        }
    }

    // MARK: Sections

    private func header(category: CategoryDisplay, progress: Double, now: Date) -> some View {
        VStack(spacing: 10) {
            ItemGlyph(category: category, progress: progress, isRetired: item.isRetired, size: 84)
                .padding(.bottom, 4)
            Text(item.displayName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(item.brand.isEmpty ? category.label : "\(item.brand) · \(category.label)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            statusBadge(now: now)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func statusBadge(now: Date) -> some View {
        if item.isRetired {
            Badge(text: String(localized: "Retired"), systemImage: "archivebox.fill", tint: .gray)
        } else if item.isPaidOff(now: now) {
            Badge(text: String(localized: "Fully amortised"), systemImage: "checkmark.seal.fill", tint: Brand.paidOff)
        } else {
            Badge(
                text: String(localized: "\(Duration.fromDays(item.daysRemaining(now: now))) remaining", comment: "Status badge. The placeholder is a duration."),
                systemImage: "hourglass",
                tint: .accentColor
            )
        }
    }

    private func lifetimeCard(category: CategoryDisplay, daysOwned: Int, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CardHeader(title: String(localized: "Lifetime"))
            VStack(alignment: .leading, spacing: 6) {
                LifetimeBar(progress: progress, tint: category.tint, height: 10)
                Text("\(Int((min(progress, 9.99) * 100).rounded()))% of expected lifetime elapsed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)

            InfoRow("Owned for", value: Duration.fromDays(daysOwned))
            Divider()
            InfoRow("Expected life", value: Duration.fromMonths(item.expectedLifetimeMonths))
            Divider()
            if let retired = item.retiredDate {
                InfoRow("Retired", value: retired.formatted(date: .abbreviated, time: .omitted))
            } else if item.isPaidOff() {
                InfoRow("Status") {
                    Label("Fully amortised — every further day is free", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Brand.paidOff)
                        .font(.footnote)
                }
            } else {
                InfoRow("Reaches expected end of life", value: item.expectedEndDate.formatted(date: .abbreviated, time: .omitted))
                Divider()
                InfoRow("Days remaining", value: "\(item.daysRemaining())")
            }
        }
        .card()
    }

    private func purchaseCard(category: CategoryDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CardHeader(title: String(localized: "Purchase"))
                .padding(.bottom, 4)
            InfoRow("Price", value: Money.string(item.price, code: item.currencyCode))
            if isForeign {
                Divider()
                InfoRow("Rate at purchase", value: "1 \(item.currencyCode) = \(item.effectiveRate.formatted(.number.precision(.fractionLength(0...6)))) \(baseCurrency)")
                Divider()
                InfoRow("In \(baseCurrency)", value: Money.string(item.priceInBase, code: baseCurrency))
            }
            if item.resaleValue > 0 {
                Divider()
                InfoRow("Recovered on resale", value: Money.string(item.resaleValue, code: item.currencyCode))
                Divider()
                InfoRow("Net cost", value: Money.string(item.netCost, code: baseCurrency))
            }
            Divider()
            InfoRow("Bought", value: item.purchaseDate.formatted(date: .abbreviated, time: .omitted))
            Divider()
            InfoRow("Category") {
                Label(category.label, systemImage: category.symbol)
                    .foregroundStyle(category.isMissing ? Color.secondary : category.tint)
            }
            Divider()
            InfoRow("Sector", value: category.sector.label)
        }
        .card()
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { item.retiredDate = item.isRetired ? nil : .now }
            } label: {
                Label(
                    item.isRetired ? String(localized: "Return to service") : String(localized: "Retire this item"),
                    systemImage: item.isRetired ? "arrow.uturn.backward" : "archivebox"
                )
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .tint(item.isRetired ? .green : .orange)
            .sensoryFeedback(.impact(weight: .medium), trigger: item.retiredDate)

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 16))

            Text("Retiring an item stops its cost calculation while retaining it in your history and statistics.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.top, 4)
    }
}

// MARK: - Pieces

private struct Badge: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: .capsule)
    }
}

/// One of the two cost-basis figures. Tapping it makes that basis the app-wide default.
private struct CostFigure: View {
    let title: String
    let value: Double
    let caption: String
    let currency: String
    let isHighlighted: Bool
    let select: () -> Void

    var body: some View {
        Button(action: { withAnimation(.snappy) { select() } }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(Money.perDay(value, code: currency))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("per day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isHighlighted ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// How this item's daily cost falls the longer it is kept, against the flat planned
/// rate. Drag across the chart to read the cost on any day.
private struct CostCurveCard: View {
    let item: Item
    let daysOwned: Int
    let tint: Color
    let currency: String

    @State private var selectedDay: Int?

    private struct Point: Identifiable {
        let day: Int
        let cost: Double
        var id: Int { day }
    }

    /// Show a bit past whichever comes later — today or the planned end of life — so
    /// the moment the curve crosses the planned line is always in view.
    private var horizon: Int { max(Int(Double(max(item.plannedDays, daysOwned)) * 1.15), 30) }

    /// Begin where the curve enters the visible range, so it sweeps in from the top
    /// instead of sitting flat against a capped axis or leaving the left side empty.
    private var start: Int { min(max(1, Int((item.netCost / yMax).rounded(.up))), horizon - 1) }

    private var points: [Point] {
        let samples = 90
        let start = self.start
        let span = Double(horizon - start)
        return (0...samples).map { i in
            let day = start + Int((span * Double(i) / Double(samples)).rounded())
            return Point(day: day, cost: cost(onDay: day))
        }
    }

    private func cost(onDay day: Int) -> Double { item.netCost / Double(max(1, day)) }

    /// Cap the y-axis so the near-vertical first weeks don't flatten everything else,
    /// while keeping both today's figure and the planned line comfortably in view.
    private var yMax: Double { max(item.plannedCostPerDay * 4, cost(onDay: max(daysOwned, 30)) * 1.5, 0.01) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                CardHeader(
                    title: String(localized: "Cost per day over time", comment: "Chart title"),
                    subtitle: String(localized: "Drag across the chart to see the cost on any day.", comment: "Chart hint")
                )
                if let selectedDay {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Money.perDay(cost(onDay: selectedDay), code: currency))
                            .font(.system(.headline, design: .rounded).monospacedDigit())
                        Text(String(localized: "over \(Duration.fromDays(selectedDay))", comment: "Caption under a cost figure. The placeholder is a duration."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }

            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Owned for", point.day), y: .value("Cost per day", min(point.cost, yMax)))
                        .foregroundStyle(LinearGradient(colors: [tint.opacity(0.25), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Owned for", point.day), y: .value("Cost per day", min(point.cost, yMax)))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.monotone)
                }

                RuleMark(y: .value("Planned", item.plannedCostPerDay))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(CostMode.planned.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                RuleMark(x: .value("Owned for", item.plannedDays))
                    .foregroundStyle(Brand.paidOff.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

                PointMark(x: .value("Owned for", daysOwned), y: .value("Cost per day", min(cost(onDay: daysOwned), yMax)))
                    .symbolSize(140)
                    .foregroundStyle(item.isRetired ? Color.secondary : tint)
                    .annotation(position: .top, spacing: 6) {
                        Text("Today")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.regularMaterial, in: .capsule)
                    }

                if let selectedDay {
                    RuleMark(x: .value("Owned for", selectedDay))
                        .foregroundStyle(.primary.opacity(0.35))
                    PointMark(x: .value("Owned for", selectedDay), y: .value("Cost per day", min(cost(onDay: selectedDay), yMax)))
                        .symbolSize(80)
                        .foregroundStyle(.primary)
                }
            }
            .chartYScale(domain: 0...yMax)
            .chartXScale(domain: start...horizon)
            .chartXSelection(value: $selectedDay)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(Money.string(amount, code: currency)).font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let day = value.as(Int.self) {
                            Text(Duration.fromDays(max(day, 1))).font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 200)
            .sensoryFeedback(.selection, trigger: selectedDay.map { $0 / 30 })
            .animation(.snappy(duration: 0.2), value: selectedDay)
        }
        .card()
    }
}
