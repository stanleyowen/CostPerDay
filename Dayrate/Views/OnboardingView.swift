import SwiftUI

/// Shown once, before the first launch's tab bar — the one place to explain the
/// app's core idea (amortised daily cost) and the "To date" vs "Planned" distinction
/// that nothing in the tab bar itself can convey. The third page lets people feel
/// that distinction by dragging, rather than reading about it.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0
    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                OnboardingPage(
                    title: String(localized: "Welcome to Dayrate", comment: "Onboarding page title"),
                    message: String(localized: "See what everything you own actually costs you — broken down to the day, not just the receipt.", comment: "Onboarding page body")
                ) {
                    WelcomeArt(isActive: page == 0)
                }
                .tag(0)

                OnboardingPage(
                    title: String(localized: "Add what you own", comment: "Onboarding page title"),
                    message: String(localized: "Log the price, purchase date and how long you expect it to last. Electronics, furniture, clothing — anything you paid for.", comment: "Onboarding page body")
                ) {
                    CategoryFanArt(isActive: page == 1)
                }
                .tag(1)

                OnboardingPage(
                    title: String(localized: "Two ways to see the cost", comment: "Onboarding page title"),
                    message: String(localized: "\"To date\" divides the price by the days you've owned it, so it falls the longer you keep something. \"Planned\" divides by the expected lifetime — the rate you budgeted for at the start.", comment: "Onboarding page body")
                ) {
                    CostDemo()
                }
                .tag(2)

                OnboardingPage(
                    title: String(localized: "Everything stays on your device", comment: "Onboarding page title"),
                    message: String(localized: "Your library is stored locally, never on a server. Export a backup or restore one anytime from Settings.", comment: "Onboarding page body")
                ) {
                    PrivacyArt(isActive: page == 3)
                }
                .tag(3)
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

/// A loose fan of the kinds of things people track.
private struct CategoryFanArt: View {
    let isActive: Bool
    @State private var spread = false

    private let categories: [ItemCategory] = [.phone, .seating, .clothing, .bicycle, .smallAppliance]

    var body: some View {
        ZStack {
            ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                let offset = Double(index) - Double(categories.count - 1) / 2
                CategoryTile(symbol: category.symbol, tint: category.tint, size: 92)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 6)
                    .rotationEffect(.degrees(spread ? offset * 12 : 0))
                    .offset(x: spread ? offset * 62 : 0, y: spread ? abs(offset) * 18 : 0)
                    .zIndex(-abs(offset))
            }
        }
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                spread = false
                withAnimation(.spring(duration: 0.8, bounce: 0.35).delay(0.1)) { spread = true }
            }
        }
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
