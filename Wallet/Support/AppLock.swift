import SwiftUI
import LocalAuthentication

/// Optional Face ID / Touch ID / passcode lock. Uses `.deviceOwnerAuthentication`, so
/// the device passcode is always a fallback and nobody can be locked out of their
/// own data by a failed biometric.
@MainActor
@Observable
final class AppLock {
    static let shared = AppLock()

    static let enabledKey = "appLockEnabled"
    static let graceKey = "appLockGraceSeconds"

    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private var backgroundedAt: Date?

    private init() {
        isLocked = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// What the device can offer, for labelling the setting.
    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "Passcode", comment: "App lock method when no biometrics are available")
        }
    }

    static var canAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func sceneDidEnterBackground() {
        backgroundedAt = .now
    }

    func sceneDidBecomeActive() {
        guard isEnabled, !isLocked, let backgroundedAt else { return }
        let grace = UserDefaults.standard.double(forKey: Self.graceKey)
        if Date.now.timeIntervalSince(backgroundedAt) >= grace {
            isLocked = true
        }
        self.backgroundedAt = nil
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "Use Passcode", comment: "Authentication fallback button")
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "Unlock your financial records", comment: "Authentication prompt reason")
            )
            if ok { withAnimation(.snappy) { isLocked = false } }
        } catch {
            // Stay locked; the user can try again from the lock screen.
        }
    }

    /// Turning the lock on is itself confirmed with authentication, so a borrowed,
    /// unlocked phone can't be used to lock the owner out (or quietly turn it off).
    func setEnabled(_ enabled: Bool) async -> Bool {
        let context = LAContext()
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: enabled
                    ? String(localized: "Turn on app lock", comment: "Authentication prompt reason")
                    : String(localized: "Turn off app lock", comment: "Authentication prompt reason")
            )
            guard ok else { return false }
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            return true
        } catch {
            return false
        }
    }
}

/// Covers the whole app while locked.
struct LockScreen: View {
    let lock: AppLock

    var body: some View {
        ZStack {
            Brand.night.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                BrandMark(size: 92)
                    .shadow(color: Brand.ember.opacity(0.4), radius: 24, y: 10)
                Text("Wallet is locked")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with \(AppLock.biometryName)", systemImage: "lock.open.fill")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(Brand.ember)
                .disabled(lock.isAuthenticating)
                .padding(.bottom, 40)
            }
        }
        .environment(\.colorScheme, .dark)
        .task { await lock.unlock() }
    }
}

/// Shown over the app whenever it isn't active, so the app switcher snapshot never
/// contains balances.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Brand.night.ignoresSafeArea()
            BrandMark(size: 80)
        }
        .environment(\.colorScheme, .dark)
        .transition(.opacity)
    }
}
