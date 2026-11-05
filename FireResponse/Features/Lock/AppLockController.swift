import LocalAuthentication
import Observation
import SwiftUI

/// Zustand der App-Sperre. Gesperrt ist die App beim Start und nach 30 Sekunden im Hintergrund, solange «Mit Face ID entsperren» an ist.
/// Ein Fehlschlag oder Abbruch lässt sie gesperrt. Ändert sich die Biometrie des Geräts, bleibt sie zu, bis die Person sich neu anmeldet.
@MainActor @Observable
final class AppLockController {
    enum Status: Equatable { case unlocked, locked, biometryChanged }

    static let gracePeriod: Duration = .seconds(30)

    private(set) var status: Status
    private(set) var isEnabled: Bool
    /// Der letzte Versuch hat nicht geklappt (nicht bei Abbruch).
    private(set) var lastAttemptFailed = false
    private(set) var isAuthenticating = false
    /// Die Ansicht fragt einmal von selbst nach dem Sperren; danach nur noch über «Entsperren» (keine Schleife nach Abbruch).
    private(set) var promptPending: Bool

    private let authenticator: any BiometricAuthenticating
    private let store: any LockStore
    private let now: @MainActor () -> ContinuousClock.Instant
    private let grace: Duration
    private var backgroundedAt: ContinuousClock.Instant?

    init(
        authenticator: any BiometricAuthenticating,
        store: any LockStore,
        grace: Duration = AppLockController.gracePeriod,
        now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
    ) {
        self.authenticator = authenticator
        self.store = store
        self.grace = grace
        self.now = now
        let enabled = store.read() != nil
        isEnabled = enabled
        status = enabled ? .locked : .unlocked
        promptPending = enabled
    }

    static func live() -> AppLockController {
        AppLockController(authenticator: LocalBiometrics(), store: KeychainLockStore())
    }

    var isLocked: Bool { status != .unlocked }
    var biometryType: LABiometryType { authenticator.biometryType }

    /// Zeit im Hintergrund zählt ab `.background`, nicht ab `.inactive` (das Face-ID-Fenster macht die App nur inaktiv).
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if backgroundedAt == nil { backgroundedAt = now() }
        case .active:
            guard let start = backgroundedAt else { return }
            backgroundedAt = nil
            if isEnabled, status == .unlocked, now() - start >= grace { lock() }
        default:
            break
        }
    }

    func lock() {
        guard isEnabled, status == .unlocked else { return }
        status = .locked
        lastAttemptFailed = false
        promptPending = true
    }

    func unlock() async {
        guard status == .locked, !isAuthenticating else { return }
        promptPending = false
        // Ohne lesbaren Stand (Biometrie gesperrt oder entfernt) prüft `authenticate` und scheitert; der Weg bleibt die Anmeldung mit Passwort.
        if let state = authenticator.domainState, store.read() != Self.marker + state {
            status = .biometryChanged
            return
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        switch await authenticator.authenticate(reason: String(localized: "Entsperre FireResponse.")) {
        case .success:
            status = .unlocked
            lastAttemptFailed = false
        case .cancelled:
            lastAttemptFailed = false
        case .failed, .unavailable:
            lastAttemptFailed = true
        }
    }

    /// Schaltet die Sperre ein, nachdem sich die Person einmal ausgewiesen hat. `false`: nicht eingeschaltet.
    func enable() async -> Bool {
        guard authenticator.biometryType != .none, !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        guard await authenticator.authenticate(reason: String(localized: "Bestätige, dass du FireResponse so entsperren willst.")) == .success else { return false }
        store.write(Self.marker + (authenticator.domainState ?? Data()))
        isEnabled = true
        return true
    }

    /// Aus (Schalter im Profil) oder nach dem Abmelden: löscht die Einstellung.
    func disable() {
        store.clear()
        isEnabled = false
        status = .unlocked
        lastAttemptFailed = false
        promptPending = false
        backgroundedAt = nil
    }

    /// Die Keychain verlangt Inhalt, darum ein Marker vor dem Stand (der auf dem Simulator leer sein kann).
    private static let marker = Data([1])
}
