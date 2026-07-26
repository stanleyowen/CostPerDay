import SwiftUI

/// Shown once, before the first launch's tab bar — the one place to explain the
/// app's core idea (amortised daily cost) and the "To date" vs "Planned" distinction
/// that nothing in the tab bar itself can convey.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "chart.line.uptrend.xyaxis",
            tint: .blue,
            title: String(localized: "Welcome to CostPerDay", comment: "Onboarding page title"),
            body: String(localized: "See what everything you own actually costs you — broken down to the day, not just the receipt.", comment: "Onboarding page body")
        ),
        OnboardingPage(
            symbol: "plus.circle.fill",
            tint: .green,
            title: String(localized: "Add what you own", comment: "Onboarding page title"),
            body: String(localized: "Log the price, purchase date and how long you expect it to last. Electronics, furniture, clothing — anything you paid for.", comment: "Onboarding page body")
        ),
        OnboardingPage(
            symbol: "arrow.left.arrow.right.circle.fill",
            tint: .orange,
            title: String(localized: "Two ways to see the cost", comment: "Onboarding page title"),
            body: String(localized: "\"To date\" divides the price by the days you've owned it, so it falls the longer you keep something. \"Planned\" divides by the expected lifetime — the rate you budgeted for at the start.", comment: "Onboarding page body")
        ),
        OnboardingPage(
            symbol: "lock.shield.fill",
            tint: .purple,
            title: String(localized: "Everything stays on your device", comment: "Onboarding page title"),
            body: String(localized: "Your library is stored locally, never on a server. Export a backup or restore one anytime from Settings.", comment: "Onboarding page body")
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    OnboardingPageView(page: item).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pages.count - 1
                     ? String(localized: "Continue", comment: "Onboarding button")
                     : String(localized: "Get Started", comment: "Onboarding button"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Button(String(localized: "Skip", comment: "Onboarding button"), action: onFinish)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .opacity(page < pages.count - 1 ? 1 : 0)
                .disabled(page == pages.count - 1)
        }
    }
}

private struct OnboardingPage {
    let symbol: String
    let tint: Color
    let title: String
    let body: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: page.symbol)
                .font(.system(size: 72))
                .foregroundStyle(page.tint)
                .frame(height: 100)
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            Spacer()
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
