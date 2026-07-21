import SwiftUI
import SwiftData

@main
struct CostPerDayApp: App {
    @State private var store = GadgetStore()

    var body: some Scene {
        WindowGroup {
            if let container = store.container {
                RootView(isTemporary: store.isTemporary)
                    .modelContainer(container)
            } else {
                StoreFailureView(message: store.failureMessage)
            }
        }
    }
}

/// Owns the SwiftData container. If the real store can't be opened — a corrupt file,
/// a schema it can't migrate, no disk space — the app falls back to an in-memory
/// store and says so, rather than killing itself on launch.
@MainActor
@Observable
final class GadgetStore {
    private(set) var container: ModelContainer?
    private(set) var isTemporary = false
    private(set) var failureMessage: String?

    init() {
        do {
            container = try ModelContainer(for: Gadget.self)
        } catch {
            let firstFailure = error.localizedDescription
            do {
                container = try ModelContainer(
                    for: Gadget.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
                isTemporary = true
            } catch {
                failureMessage = firstFailure
            }
        }
        container?.mainContext.undoManager = UndoManager()

        #if DEBUG
        if let context = container?.mainContext, CommandLine.arguments.contains("-seedSampleData") {
            SampleData.seedIfEmpty(in: context)
        }
        #endif
    }
}

struct RootView: View {
    var isTemporary = false

    var body: some View {
        TabView {
            Tab("Gadgets", systemImage: "square.stack.3d.up") {
                GadgetListView()
            }
            Tab("Dashboard", systemImage: "chart.bar.xaxis") {
                DashboardView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .overlay(alignment: .top) {
            if isTemporary {
                TemporaryStoreBanner()
            }
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
            Text(message ?? "The gadget database couldn't be opened. Restarting the app may help; if not, reinstalling will start you with an empty library.")
        }
    }
}
