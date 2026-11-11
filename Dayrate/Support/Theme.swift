import SwiftUI

/// The visual identity, in one place. The whole brand hangs off a single idea — the
/// falling "price ÷ days" curve — drawn in a warm ember-to-amber gradient on deep ink.
enum Brand {
    static let ember = Color(red: 1.000, green: 0.373, blue: 0.227) // #FF5F3A
    static let amber = Color(red: 1.000, green: 0.698, blue: 0.247) // #FFB23F
    static let ink = Color(red: 0.086, green: 0.078, blue: 0.133)   // #161422
    static let inkRaised = Color(red: 0.180, green: 0.133, blue: 0.259) // #2E2242

    /// Success state: an item that has outlived its expected lifetime.
    static let paidOff = Color.green

    static let flame = LinearGradient(colors: [ember, amber], startPoint: .leading, endPoint: .trailing)
    static let night = LinearGradient(colors: [inkRaised, ink], startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - The curve

/// The shape behind the logo, the hero cards and the onboarding demo: cost per day
/// falling as days owned grows, i.e. a normalised `k / (t + k)` hyperbola.
struct BrandCurve: Shape {
    /// How sharply the curve drops. Smaller is steeper.
    var steepness: CGFloat = 0.15
    /// Where the curve levels out, as a fraction of the height above the bottom edge.
    var floor: CGFloat = 0.1

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 64
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let point = CGPoint(x: rect.minX + t * rect.width, y: rect.minY + (1 - height(at: t)) * rect.height)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// 1 at the start, `floor` at the end.
    func height(at t: CGFloat) -> CGFloat {
        let k = steepness
        let end = k / (1 + k)
        let normalised = (k / (t + k) - end) / (1 - end)
        return floor + (1 - floor) * normalised
    }
}

/// The app's mark: the cost curve settling into a white "today" dot above a week of
/// days, on ink. Geometry matches `Design/make_icon.py`, so the mark reads the same
/// inside the app as on the home screen.
struct BrandMark: View {
    var size: CGFloat = 64
    /// 0…1, for drawing the curve in on first appearance.
    var drawProgress: CGFloat = 1

    var body: some View {
        let curve = BrandCurve()
        let rect = CGRect(x: 0.27 * size, y: 0.19 * size, width: 0.50 * size, height: 0.47 * size)
        let end = CGPoint(x: rect.maxX, y: rect.minY + (1 - curve.height(at: 1)) * rect.height)
        let dot = size * 0.13
        let tick = size * 0.052

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .fill(Brand.night)

            curve
                .trim(from: 0, to: drawProgress)
                .stroke(Brand.ember.opacity(0.45), style: StrokeStyle(lineWidth: size * 0.16, lineCap: .round))
                .blur(radius: size * 0.04)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)

            curve
                .trim(from: 0, to: drawProgress)
                .stroke(Brand.flame, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)

            ForEach(0..<7, id: \.self) { day in
                Circle()
                    .fill(day == 6 ? AnyShapeStyle(Brand.amber) : AnyShapeStyle(.white.opacity(0.3)))
                    .frame(width: tick, height: tick)
                    .position(x: rect.minX + rect.width * CGFloat(day) / 6, y: size * 0.80)
            }

            ZStack {
                Circle().fill(Brand.ink).frame(width: dot + size * 0.03, height: dot + size * 0.03)
                Circle().fill(.white).frame(width: dot, height: dot)
            }
            .position(end)
                .scaleEffect(drawProgress >= 1 ? 1 : 0.01, anchor: UnitPoint(x: end.x / size, y: end.y / size))
                .animation(.spring(duration: 0.4, bounce: 0.5), value: drawProgress >= 1)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.2237, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Surfaces

extension View {
    /// The standard content card: a raised rounded surface on the grouped background.
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22, style: .continuous))
    }
}

/// Dark hero surface with the brand curve glowing faintly behind the content.
struct HeroBackground: View {
    var body: some View {
        ZStack {
            Brand.night
            BrandCurve(steepness: 0.22, floor: 0.18)
                .stroke(Brand.flame, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .opacity(0.55)
                .padding(.top, 18)
                .padding(.bottom, 26)
                .padding(.leading, -10)
                .blur(radius: 0.4)
            BrandCurve(steepness: 0.22, floor: 0.18)
                .stroke(Brand.ember, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .opacity(0.18)
                .blur(radius: 16)
                .padding(.top, 18)
                .padding(.bottom, 26)
        }
    }
}

// MARK: - Category glyph

/// A category icon wrapped in a ring showing how far through its expected life the
/// item is. The ring turns green once the item is fully amortised.
struct ItemGlyph: View {
    let category: CategoryDisplay
    var progress: Double = 0
    var isRetired = false
    var size: CGFloat = 44

    private var clamped: Double { progress.isFinite ? min(1, max(0, progress)) : 0 }
    private var isPaidOff: Bool { clamped >= 1 && !isRetired }
    private var tint: Color { isRetired || category.isMissing ? .secondary : category.tint }
    private var lineWidth: CGFloat { max(2.5, size * 0.075) }

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.14))
                .padding(lineWidth + 1.5)
            Image(systemName: category.symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(tint)
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(isPaidOff ? Brand.paidOff : tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isPaidOff {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size * 0.32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Brand.paidOff)
                    .background(Circle().fill(Color(.systemBackground)).padding(1))
                    .offset(x: size * 0.36, y: size * 0.36)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A rounded tinted tile for a category, used where no progress applies.
struct CategoryTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Chips

/// A capsule filter or option. Selected chips fill with the accent colour.
struct Chip: View {
    let title: String
    var systemImage: String?
    var isSelected = false
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                Capsule().fill(isSelected ? AnyShapeStyle(tint) : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            }
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.08))
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Cost basis switch

/// The "To date" / "Planned" switch, with an info button explaining the difference.
/// Shared by the Items hero and the Dashboard so the choice reads the same everywhere.
struct CostModePicker: View {
    @Binding var mode: CostMode
    /// Styles the control for the dark hero card rather than the grouped background.
    var onDark = false

    @Namespace private var namespace
    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(CostMode.allCases) { option in
                    let selected = option == mode
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { mode = option }
                    } label: {
                        Text(option.label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(foreground(selected: selected))
                            .background {
                                if selected {
                                    Capsule()
                                        .fill(onDark ? AnyShapeStyle(.white) : AnyShapeStyle(Color(.systemBackground)))
                                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                        .matchedGeometryEffect(id: "selection", in: namespace)
                                }
                            }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(3)
            .background(onDark ? AnyShapeStyle(.white.opacity(0.14)) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .capsule)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Cost basis"))

            Button {
                showInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(onDark ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Cost basis"))
            .popover(isPresented: $showInfo) {
                CostModeExplainer()
                    .presentationCompactAdaptation(.popover)
            }
        }
        .sensoryFeedback(.selection, trigger: mode)
    }

    private func foreground(selected: Bool) -> AnyShapeStyle {
        if onDark {
            return selected ? AnyShapeStyle(Brand.ink) : AnyShapeStyle(.white.opacity(0.8))
        }
        return selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }
}

/// Explains both cost bases side by side.
struct CostModeExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(CostMode.allCases) { mode in
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.label).font(.subheadline.weight(.semibold))
                    Text(mode.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(idealWidth: 300, maxWidth: 320)
    }
}

// MARK: - Periods

/// The hero figure can be read per day, week, month or year — tap to cycle.
enum CostPeriod: String, CaseIterable {
    case day, week, month, year

    var days: Double {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30.4375
        case .year: 365.25
        }
    }

    var label: String {
        switch self {
        case .day: String(localized: "per day", comment: "Cost equivalence label")
        case .week: String(localized: "per week", comment: "Cost equivalence label")
        case .month: String(localized: "per month", comment: "Cost equivalence label")
        case .year: String(localized: "per year", comment: "Cost equivalence label")
        }
    }

    var next: CostPeriod {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    func format(_ perDay: Double, code: String) -> String {
        self == .day ? Money.perDay(perDay, code: code) : Money.string(perDay * days, code: code)
    }
}

// MARK: - Small pieces

/// A label–value row inside a card.
struct InfoRow<Value: View>: View {
    let title: Text
    @ViewBuilder let value: Value

    init(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.title = Text(title)
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            title.foregroundStyle(.secondary)
            Spacer(minLength: 8)
            value
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 10)
    }
}

extension InfoRow where Value == Text {
    init(_ title: LocalizedStringKey, value: String) {
        self.init(title) { Text(value).foregroundStyle(.primary) }
    }
}

/// Section heading used above cards on scrolling screens.
struct CardHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Item {
    var displayName: String {
        name.isEmpty ? String(localized: "Untitled", comment: "Fallback name for an unnamed item") : name
    }
}
