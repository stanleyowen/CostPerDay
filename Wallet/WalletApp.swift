import SwiftUI
import SwiftData

@main
struct WalletApp: App {
    @State private var store = DataStore.shared
    @State private var router = AppRouter.shared
    @State private var lock = AppLock.shared

    var body: some Scene {
        WindowGroup {
            if let container = store.container {
                RootView(isTemporary: store.isTemporary)
                    .modelContainer(container)
                    .environment(router)
                    .environment(lock)
            } else {
                StoreFailureView(message: store.failureMessage)
            }
        }
    }
}

struct RootView: View {
    var isTemporary = false

    @Environment(AppRouter.self) private var router
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(AppLock.enabledKey) private var lockEnabled = false
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Transactions", systemImage: "list.bullet.rectangle.portrait.fill", value: AppTab.transactions) {
                TransactionsView()
            }
            Tab("Reports", systemImage: "chart.pie.fill", value: AppTab.reports) {
                ReportsView()
            }
            Tab("Items", systemImage: "shippingbox.fill", value: AppTab.items) {
                ItemListView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .sensoryFeedback(.selection, trigger: router.tab)
        .overlay(alignment: .top) {
            if isTemporary {
                TemporaryStoreBanner()
            }
        }
        .sheet(item: $router.composer) { draft in
            RecordEditView(record: nil, prefill: draft) { item in
                router.itemToConfirm = item
            }
        }
        .sheet(item: $router.itemToConfirm) { item in
            ItemEditView(item: item, isNew: true, prefilled: true)
        }
        .overlay {
            if lockEnabled && lock.isLocked {
                LockScreen(lock: lock)
                    .transition(.opacity)
            } else if lockEnabled && scenePhase != .active && !lock.isAuthenticating {
                PrivacyCover()
            }
        }
        .animation(.snappy(duration: 0.2), value: lock.isLocked)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: lock.sceneDidEnterBackground()
            case .active: lock.sceneDidBecomeActive()
            default: break
            }
        }
        .onAppear {
            #if DEBUG
            let arguments = CommandLine.arguments
            if arguments.contains("-skipOnboarding") { hasCompletedOnboarding = true }
            if let flag = arguments.firstIndex(of: "-initialTab"), flag + 1 < arguments.count,
               let tab = AppTab(rawValue: arguments[flag + 1]) {
                router.tab = tab
            }
            if arguments.contains("-openComposer") { router.compose() }
            #endif
            showOnboarding = !hasCompletedOnboarding
        }
        // Settings can replay the introduction by clearing the flag.
        .onChange(of: hasCompletedOnboarding) { _, done in showOnboarding = !done }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
                showOnboarding = false
            }
            .tint(Color.accentColor)
            .interactiveDismissDisabled()
        }
    }
}

/// Shown when we fell back to an in-memory store — the app still works, but nothing
/// entered now will survive a relaunch, and the user needs to know that up front.
private struct TemporaryStoreBanner: View {
    var body: some View {
        Label("Saving is unavailable — changes will be lost when you quit.", systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.orange)
    }
}

private struct StoreFailureView: View {
    let message: String?

    var body: some View {
        ContentUnavailableView {
            Label("Can't open your library", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message ?? "Your item database couldn't be opened. Restarting the app may help; if not, reinstalling will start you with an empty library.")
        }
    }
}
