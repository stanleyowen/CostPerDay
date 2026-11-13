import SwiftUI

/// The visual identity, in one place. Wallet's mark is a classic leather wallet
/// (`BrandMark`); the interface accent is a warm ember-to-amber gradient on deep
/// ink, and the falling "price ÷ days" curve from the ownership tracker lives on in
/// the hero cards and onboarding.
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

/// The app's mark: a classic brown leather bifold with saddle stitching and a snap
/// strap, three cards (coral, gold, white) fanned out of the top, on warm cream.
/// Geometry and colours match `Design/make_icon.py`, so the mark reads the same in
/// the app and on the home screen.
struct BrandMark: View {
    var size: CGFloat = 64
    /// 0…1, for drawing the mark in on first appearance: the cards slide up into
    /// place, then the snap pops onto the strap.
    var drawProgress: CGFloat = 1

    /// Shared with the icon script — all in unit coordinates, angles clockwise.
    enum Geometry {
        /// Back to front.
        static let cards: [(rect: CGRect, angle: Double)] = [
            (CGRect(x: 0.23, y: 0.17, width: 0.44, height: 0.28), -14),
            (CGRect(x: 0.29, y: 0.19, width: 0.44, height: 0.28), -2),
            (CGRect(x: 0.34, y: 0.23, width: 0.44, height: 0.28), 9),
        ]
        static let cardRadius: CGFloat = 0.035
        /// The magnetic stripe, as a fraction of the card's height.
        static let stripe: ClosedRange<CGFloat> = 0.22...0.38
        static let body = CGRect(x: 0.16, y: 0.38, width: 0.68, height: 0.42)
        static let bodyRadius: CGFloat = 0.09
        /// The body's stitching; its right edge is left out because the strap covers it.
        static let bodyStitch = CGRect(x: 0.19, y: 0.41, width: 0.62, height: 0.36)
        static let bodyStitchRadius: CGFloat = 0.07
        static let strap = CGRect(x: 0.60, y: 0.50, width: 0.30, height: 0.18)
        static let strapStitch = CGRect(x: 0.625, y: 0.522, width: 0.25, height: 0.136)
        static let strapStitchRadius: CGFloat = 0.065
        static let snap = CGPoint(x: 0.755, y: 0.59)
        static let snapRadius: CGFloat = 0.042
        static let snapFace = CGPoint(x: 0.755, y: 0.585)
        static let snapFaceRadius: CGFloat = 0.03
        static let backgroundCenter = UnitPoint(x: 0.5, y: 0.35)
        static let backgroundRadius: CGFloat = 0.9
        static let cornerRadius: CGFloat = 0.2237
    }

    private enum Palette {
        static let background = [rgb(255, 244, 226), rgb(246, 222, 186)]
        /// Fill and stripe, back to front.
        static let cards = [(rgb(255, 120, 92), rgb(210, 80, 60)),
                            (rgb(255, 206, 84), rgb(220, 160, 40)),
                            (rgb(250, 250, 252), rgb(40, 168, 160))]
        static let body = [rgb(178, 110, 62), rgb(130, 74, 38)]
        static let bodyShadow = rgb(90, 50, 20)
        static let stitch = rgb(236, 196, 150)
        static let strap = [rgb(150, 88, 46), rgb(112, 62, 30)]
        static let strapShadow = rgb(60, 30, 10)
        static let strapStitch = rgb(226, 184, 138)
        static let snapRim = rgb(210, 170, 90)
        static let snapFace = rgb(244, 214, 140)

        static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(red: r / 255, green: g / 255, blue: b / 255)
        }
    }

    var body: some View {
        let g = Geometry.self
        let rise = min(1, drawProgress / 0.75)
        // Cards start tucked down inside the wallet and rise as the mark draws in,
        // the back ones a little later than the front.
        let drop = (1 - rise) * 0.2 * size
        let snapIn = drawProgress >= 1

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: size * g.cornerRadius, style: .continuous)
                .fill(RadialGradient(colors: Palette.background, center: g.backgroundCenter,
                                     startRadius: 0, endRadius: g.backgroundRadius * size))

            ForEach(g.cards.indices, id: \.self) { i in
                card(g.cards[i].rect, angle: g.cards[i].angle, fill: Palette.cards[i].0, stripe: Palette.cards[i].1)
                    .offset(y: drop * (1 + 0.15 * CGFloat(g.cards.count - 1 - i)))
            }

            RoundedRectangle(cornerRadius: size * g.bodyRadius, style: .continuous)
                .fill(LinearGradient(colors: Palette.body, startPoint: .top, endPoint: .bottom))
                .frame(width: g.body.width * size, height: g.body.height * size)
                .shadow(color: Palette.bodyShadow.opacity(0.35), radius: size * 0.035, y: size * 0.025)
                .offset(x: g.body.minX * size, y: g.body.minY * size)

            Stitches(rect: g.bodyStitch, radius: g.bodyStitchRadius, dash: 0.028, gap: 0.02, skipRight: true)
                .stroke(Palette.stitch, lineWidth: 0.008 * size)
                .frame(width: size, height: size)

            Capsule()
                .fill(LinearGradient(colors: Palette.strap, startPoint: .top, endPoint: .bottom))
                .frame(width: g.strap.width * size, height: g.strap.height * size)
                .shadow(color: Palette.strapShadow.opacity(0.35), radius: size * 0.012, y: size * 0.01)
                .offset(x: g.strap.minX * size, y: g.strap.minY * size)

            Stitches(rect: g.strapStitch, radius: g.strapStitchRadius, dash: 0.02, gap: 0.016)
                .stroke(Palette.strapStitch, lineWidth: 0.006 * size)
                .frame(width: size, height: size)

            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(Palette.snapRim)
                    .frame(width: g.snapRadius * 2 * size, height: g.snapRadius * 2 * size)
                    .position(x: g.snap.x * size, y: g.snap.y * size)
                Circle()
                    .fill(Palette.snapFace)
                    .frame(width: g.snapFaceRadius * 2 * size, height: g.snapFaceRadius * 2 * size)
                    .position(x: g.snapFace.x * size, y: g.snapFace.y * size)
            }
            .frame(width: size, height: size)
            .scaleEffect(snapIn ? 1 : 0.01, anchor: UnitPoint(x: g.snap.x, y: g.snap.y))
            .animation(.spring(duration: 0.4, bounce: 0.5), value: snapIn)
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * g.cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private func card(_ rect: CGRect, angle: Double, fill: Color, stripe: Color) -> some View {
        let g = Geometry.self
        return RoundedRectangle(cornerRadius: g.cardRadius * size, style: .continuous)
            .fill(fill)
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(stripe)
                    .frame(height: (g.stripe.upperBound - g.stripe.lowerBound) * rect.height * size)
                    .offset(y: g.stripe.lowerBound * rect.height * size)
            }
            .clipShape(.rect(cornerRadius: g.cardRadius * size, style: .continuous))
            .frame(width: rect.width * size, height: rect.height * size)
            .shadow(color: .black.opacity(0.3), radius: size * 0.012, y: size * 0.008)
            .rotationEffect(.degrees(angle))
            .offset(x: rect.minX * size, y: rect.minY * size)
    }

    /// Saddle stitching: dashes along a rounded rect's straight edges, in unit
    /// coordinates of the shape's frame. Each edge holds a whole number of dash+gap
    /// steps, stretched to fit, with half a gap at each end — the same layout as
    /// `stitch_dashes` in the icon script.
    private struct Stitches: Shape {
        var rect: CGRect
        var radius: CGFloat
        var dash: CGFloat
        var gap: CGFloat
        var skipRight = false

        func path(in frame: CGRect) -> Path {
            let r = rect, k = radius
            var edges: [(CGPoint, CGPoint)] = [
                (CGPoint(x: r.minX + k, y: r.minY), CGPoint(x: r.maxX - k, y: r.minY)),
                (CGPoint(x: r.maxX - k, y: r.maxY), CGPoint(x: r.minX + k, y: r.maxY)),
                (CGPoint(x: r.minX, y: r.maxY - k), CGPoint(x: r.minX, y: r.minY + k)),
            ]
            if !skipRight {
                edges.append((CGPoint(x: r.maxX, y: r.minY + k), CGPoint(x: r.maxX, y: r.maxY - k)))
            }
            var path = Path()
            for (a, b) in edges {
                let length = hypot(b.x - a.x, b.y - a.y)
                let n = Int(length / (dash + gap))
                guard n > 0 else { continue }
                let step = length / CGFloat(n)
                for i in 0..<n {
                    let t0 = (CGFloat(i) * step + gap / 2) / length
                    let t1 = (CGFloat(i) * step + gap / 2 + dash) / length
                    path.move(to: point(a, b, t0, in: frame))
                    path.addLine(to: point(a, b, t1, in: frame))
                }
            }
            return path
        }

        private func point(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat, in frame: CGRect) -> CGPoint {
            CGPoint(x: frame.minX + (a.x + (b.x - a.x) * t) * frame.width,
                    y: frame.minY + (a.y + (b.y - a.y) * t) * frame.height)
        }
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
    /// Off where the card draws its own chart, so two curves don't compete.
    var showsCurve = true

    var body: some View {
        ZStack {
            Brand.night
            if showsCurve {
                curves
            }
        }
    }

    private var curves: some View {
        ZStack {
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
