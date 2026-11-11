import SwiftUI

/// Shown once, before the first launch's tab bar: what Wallet does (track every
/// transaction, report on it, and follow what owned things cost per day), and the
/// "To date" vs "Planned" distinction that nothing in the tab bar can convey. The
/// cost page lets people feel that distinction by dragging, rather than reading.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0
    private let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                OnboardingPage(
                    title: String(localized: "Welcome to Wallet", comment: "Onboarding page title"),
                    message: String(localized: "Every transaction, and everything it bought. Track your spending, see where it goes, and know what the things you own really cost.", comment: "Onboarding page body")
                ) {
                    WelcomeArt(isActive: page == 0)
                }
                .tag(0)

                OnboardingPage(
                    title: String(localized: "Log it in seconds", comment: "Onboarding page title"),
                    message: String(localized: "A calculator keypad, suggestions learned from your own history, and Shortcuts and Siri for when you'd rather not open the app.", comment: "Onboarding page body")
                ) {
                    TransactionStackArt(isActive: page == 1)
                }
                .tag(1)

                OnboardingPage(
                    title: String(localized: "See where it goes", comment: "Onboarding page title"),
                    message: String(localized: "Reports by category, label and account, with trends, budgets and a spending calendar.", comment: "Onboarding page body")
                ) {
                    ReportArt(isActive: page == 2)
                }
                .tag(2)

                OnboardingPage(
                    title: String(localized: "Two ways to see the cost", comment: "Onboarding page title"),
                    message: String(localized: "\"To date\" divides the price by the days you've owned it, so it falls the longer you keep something. \"Planned\" divides by the expected lifetime — the rate you budgeted for at the start.", comment: "Onboarding page body")
                ) {
                    CostDemo()
                }
                .tag(3)

                OnboardingPage(
                    title: String(localized: "Everything stays on your device", comment: "Onboarding page title"),
                    message: String(localized: "Your library is stored locally, never on a server. Export a backup or restore one anytime from Settings.", comment: "Onboarding page body")
                ) {
                    PrivacyArt(isActive: page == 4)
                }
                .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            PageDots(count: pageCount, current: page)
                .padding(.bottom, 20)

            Button {
                if page < pageCount - 1 {
                    withAnimation(.snappy) { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pageCount - 1
                     ? String(localized: "Continue", comment: "Onboarding button")
                     : String(localized: "Get Started", comment: "Onboarding button"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentTransition(.opacity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.horizontal, 24)

            Button(String(localized: "Skip", comment: "Onboarding button"), action: onFinish)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .opacity(page < pageCount - 1 ? 1 : 0)
                .disabled(page == pageCount - 1)
        }
        .background(Color(.systemGroupedBackground))
        .sensoryFeedback(.selection, trigger: page)
    }
}

// MARK: - Layout

private struct OnboardingPage<Art: View>: View {
    let title: String
    let message: String
    @ViewBuilder let art: Art

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 12)
            art
                .frame(maxWidth: .infinity)
                .frame(height: 300)
            VStack(spacing: 12) {
                Text(title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 12)
        }
    }
}

private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.3)))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityHidden(true)
    }
}

// MARK: - Page art

/// The mark, with its curve drawing itself in.
private struct WelcomeArt: View {
    let isActive: Bool
    @State private var progress: CGFloat = 0

    var body: some View {
        BrandMark(size: 168, drawProgress: progress)
            .shadow(color: Brand.ember.opacity(0.35), radius: 30, y: 14)
            .onChange(of: isActive, initial: true) { _, active in
                guard active else { return }
                progress = 0
                withAnimation(.easeOut(duration: 1.4).delay(0.2)) { progress = 1 }
            }
    }
}

/// Transactions dropping into a list, one after another.
private struct TransactionStackArt: View {
    let isActive: Bool
    @State private var shown = 0

    private let samples: [(RecordCategory, String, Double)] = [
        (.barCafe, "Flat white", 4.5),
        (.groceries, "Weekly shop", 62.3),
        (.publicTransport, "Metro card", 20),
        (.electronics, "Headphones", 179),
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                HStack(spacing: 12) {
                    CategoryTile(symbol: sample.0.symbol, tint: sample.0.tint, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sample.1).font(.subheadline.weight(.semibold))
                        Text(sample.0.label).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("−" + sample.2.formatted(.number.precision(.fractionLength(0...2))))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                    if sample.0 == .electronics {
                        Image(systemName: "shippingbox.fill").font(.caption).foregroundStyle(Brand.ember)
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                .opacity(index < shown ? 1 : 0)
                .offset(y: index < shown ? 0 : -24)
                .scaleEffect(index < shown ? 1 : 0.95)
            }
        }
        .padding(.horizontal, 32)
        .onChange(of: isActive, initial: true) { _, active in
            guard active else { return }
            shown = 0
            for index in samples.indices {
                withAnimation(.spring(duration: 0.5, bounce: 0.35).delay(0.15 + Double(index) * 0.22)) { shown = index + 1 }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A donut sweeping in, with its legend.
private struct ReportArt: View {
    let isActive: Bool
    @State private var sweep: CGFloat = 0

    private let slices: [(RecordGroup, Double)] = [(.food, 0.34), (.housing, 0.24), (.transport, 0.14), (.shopping, 0.16), (.life, 0.12)]

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                    let start = slices.prefix(index).reduce(0) { $0 + $1.1 }
                    Circle()
                        .trim(from: start * sweep, to: (start + slice.1) * sweep - 0.006)
                        .stroke(slice.0.tint.gradient, style: StrokeStyle(lineWidth: 30, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: "chart.pie.fill")
                    .font(.title)
                    .foregroundStyle(Brand.flame)
            }
            .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                    HStack(spacing: 8) {
                        Circle().fill(slice.0.tint).frame(width: 9, height: 9)
                        Text(slice.0.label).font(.caption.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(slice.1.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 150)
            .opacity(sweep)
        }
        .onChange(of: isActive, initial: true) { _, active in
            guard active else { return }
            sweep = 0
            withAnimation(.easeOut(duration: 1.1).delay(0.15)) { sweep = 1 }
        }
        .accessibilityHidden(true)
    }
}

/// Drag the slider and watch "To date" fall towards — then below — "Planned".
/// A $1,200-ish laptop expected to last five years, in the user's own currency.
private struct CostDemo: View {
    @AppStorage("baseCurrency") private var baseCurrency = Currency.deviceDefault
    @State private var days: Double = 120

    private let price: Double = 1200
    private let plannedDays: Double = 5 * 365.25
    private let maxDays: Double = 6 * 365.25

    private var toDate: Double { price / max(days, 1) }
    private var planned: Double { price / plannedDays }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                CategoryTile(symbol: ItemCategory.laptop.symbol, tint: ItemCategory.laptop.tint, size: 38)
                Text(ItemCategory.laptop.label).font(.headline)
                Spacer()
                Text(Money.string(price, code: baseCurrency))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                figure(CostMode.actual.label, toDate, highlighted: true)
                figure(CostMode.planned.label, planned, highlighted: false)
            }

            GeometryReader { geo in
                let rect = CGRect(origin: .zero, size: geo.size)
                let curve = BrandCurve(steepness: 0.08, floor: 0.06)
                let t = CGFloat(days / maxDays)
                ZStack(alignment: .topLeading) {
                    curve.stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    curve.trim(from: 0, to: t)
                        .stroke(Brand.flame, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(Brand.ember, lineWidth: 3))
                        .frame(width: 16, height: 16)
                        .position(x: rect.width * t, y: (1 - curve.height(at: t)) * rect.height)
                }
            }
            .frame(height: 70)

            VStack(spacing: 4) {
                Slider(value: $days, in: 7...maxDays)
                    .tint(Brand.ember)
                    .accessibilityLabel(Text("Owned for"))
                    .accessibilityValue(Text(Duration.fromDays(Int(days))))
                HStack {
                    Text("Owned for")
                    Spacer()
                    Text(Duration.fromDays(Int(days)))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: days))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 24)
        .sensoryFeedback(.selection, trigger: Int(days / 90))
        .sensoryFeedback(.success, trigger: toDate <= planned)
    }

    private func figure(_ title: String, _ value: Double, highlighted: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(highlighted ? AnyShapeStyle(Brand.ember) : AnyShapeStyle(.secondary))
            Text(Money.perDay(value, code: baseCurrency))
                .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                .contentTransition(.numericText(value: value))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("per day").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            highlighted ? AnyShapeStyle(Brand.ember.opacity(0.1)) : AnyShapeStyle(Color(.tertiarySystemFill)),
            in: .rect(cornerRadius: 16, style: .continuous)
        )
    }
}

private struct PrivacyArt: View {
    let isActive: Bool
    @State private var appear = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Brand.ember.opacity(0.08))
                .frame(width: 250, height: 250)
                .scaleEffect(appear ? 1 : 0.7)
            Circle()
                .fill(Brand.ember.opacity(0.12))
                .frame(width: 180, height: 180)
                .scaleEffect(appear ? 1 : 0.7)
            Image(systemName: "iphone")
                .font(.system(size: 110, weight: .light))
                .foregroundStyle(.primary.opacity(0.85))
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Brand.night, in: .circle)
                .overlay(Circle().strokeBorder(Brand.flame, lineWidth: 3))
                .offset(x: 46, y: 40)
                .scaleEffect(appear ? 1 : 0.4)
        }
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                appear = false
                withAnimation(.spring(duration: 0.7, bounce: 0.4).delay(0.1)) { appear = true }
            }
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
