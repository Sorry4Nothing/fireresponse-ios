import LocalAuthentication
import SwiftUI

extension View {
    /// App-Sperre mit Face ID oder Touch ID und Abdeckung beim App-Wechsel (Issue #5).
    /// Legt den `AppLockController` in die Umgebung, damit das Profil die Sperre ein- und ausschalten kann.
    func appLock() -> some View { modifier(AppLockModifier()) }
}

private struct AppLockModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = AppLockController.live()

    func body(content: Content) -> some View {
        // Die Abdeckung liegt, sobald die App nicht aktiv ist: das System fotografiert den App-Umschalter erst danach.
        let covered = controller.isLocked || scenePhase != .active
        content
            .environment(controller)
            .accessibilityHidden(covered)
            .overlay {
                if covered {
                    LockScreen(
                        controller: controller,
                        isActive: scenePhase == .active,
                        signIn: { await SignOut.perform(model: model, lock: controller) }
                    )
                }
            }
            .onChange(of: scenePhase) { _, phase in controller.scenePhaseChanged(phase) }
    }
}

/// Fläche `surface` mit Flamme über dem Inhalt. Gesperrt kommen Titel, Satz und «Entsperren» dazu; nur abgedeckt (App-Umschalter) bleibt die Flamme.
struct LockScreen: View {
    let controller: AppLockController
    var isActive = true
    var signIn: () async -> Void = {}
    @AccessibilityFocusState private var titleFocused: Bool

    private struct Trigger: Hashable {
        let status: AppLockController.Status
        let isActive: Bool
    }

    var body: some View {
        // Scrollbar, damit bei der grössten Schrift nichts abgeschnitten wird oder sich überlagert.
        ScrollView { content }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center, for: .alignment)
            .background(Color.frSurface.ignoresSafeArea())
            .task(id: Trigger(status: controller.status, isActive: isActive)) {
                guard controller.isLocked, isActive else { return }
                titleFocused = true
                if controller.status == .locked, controller.promptPending { await controller.unlock() }
            }
    }

    private var content: some View {
        VStack(spacing: Spacing.s4) {
            Image(systemName: "flame.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.frPrimary)
                .frame(width: 72, height: 72)
                .background(Color.frSecondaryContainer, in: .circle)
                .accessibilityHidden(true)
            if controller.isLocked {
                Text("Gesperrt")
                    .font(.frTitle2)
                    .foregroundStyle(Color.frOnSurface)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Text(message).font(.body).foregroundStyle(Color.frOnSurfaceVariant).multilineTextAlignment(.center)
                if controller.lastAttemptFailed {
                    Notice(.error, title: "Das Entsperren hat nicht geklappt.", message: "Versuche es noch einmal.")
                }
                VStack(spacing: Spacing.s3) {
                    if controller.status == .locked {
                        FRButton("Entsperren", systemImage: controller.biometryType == .touchID ? "touchid" : "faceid") {
                            Task { await controller.unlock() }
                        }
                        .disabled(controller.isAuthenticating)
                        FRButton("Mit Passwort anmelden", kind: .text) { Task { await signIn() } }
                    } else {
                        FRButton("Mit Passwort anmelden") { Task { await signIn() } }
                    }
                }
                .frame(maxWidth: Sizes.contentMax)
            }
        }
        .padding(Spacing.s6)
        .frame(maxWidth: .infinity)
    }

    private var message: LocalizedStringResource {
        switch (controller.status, controller.biometryType) {
        case (.biometryChanged, .touchID): "Touch ID auf diesem Gerät hat sich geändert. Melde dich zur Sicherheit neu an."
        case (.biometryChanged, _): "Face ID auf diesem Gerät hat sich geändert. Melde dich zur Sicherheit neu an."
        case (_, .touchID): "Entsperre FireResponse mit Touch ID."
        default: "Entsperre FireResponse mit Face ID."
        }
    }
}

#if DEBUG
private struct LockDemoAuthenticator: BiometricAuthenticating {
    var biometryType: LABiometryType { .faceID }
    var domainState: Data? { Data([7]) }
    func authenticate(reason: String) async -> BiometricOutcome { .failed }
}

private struct LockDemoStore: LockStore {
    func read() -> Data? { Data([1, 7]) }
    func write(_ baseline: Data) {}
    func clear() {}
}

@MainActor private func demoController() -> AppLockController {
    let controller = AppLockController(authenticator: LockDemoAuthenticator(), store: LockDemoStore())
    return controller
}

#Preview("Gesperrt, Nacht, AX5") { LockScreen(controller: demoController(), isActive: false).preferredColorScheme(.dark).dynamicTypeSize(.accessibility5) }
#Preview("Gesperrt, Tag") { LockScreen(controller: demoController(), isActive: false).preferredColorScheme(.light) }
#endif
