import Foundation
import LocalAuthentication

/// Ergebnis einer Prüfung mit Gesicht oder Fingerabdruck.
nonisolated enum BiometricOutcome: Equatable, Sendable {
    case success
    /// Die Person hat abgebrochen (oder das System): keine Fehlermeldung nötig.
    case cancelled
    /// Nicht erkannt oder zu viele Versuche.
    case failed
    /// Keine Biometrie eingerichtet oder gesperrt.
    case unavailable
}

/// Naht zur Biometrie des Geräts, damit die Sperrlogik ohne Gerät prüfbar bleibt (SR-Biometrie).
nonisolated protocol BiometricAuthenticating: Sendable {
    /// `.none`, wenn keine Biometrie eingerichtet ist.
    var biometryType: LABiometryType { get }
    /// Stand der eingerichteten Biometrie: ändert sich, sobald ein Gesicht oder Finger dazukommt oder entfällt.
    var domainState: Data? { get }
    func authenticate(reason: String) async -> BiometricOutcome
}

/// Nur starke Biometrie (`deviceOwnerAuthenticationWithBiometrics`): kein Gerätecode als Ersatz, wie bei Android (`BIOMETRIC_STRONG`).
nonisolated struct LocalBiometrics: BiometricAuthenticating {
    private func probe() -> LAContext? {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) ? context : nil
    }

    var biometryType: LABiometryType { probe()?.biometryType ?? .none }
    var domainState: Data? { probe()?.domainState.biometry.stateHash }

    func authenticate(reason: String) async -> BiometricOutcome {
        let context = LAContext()
        // Ohne Titel gibt es keinen «Gerätecode eingeben»-Knopf nach einem Fehlversuch.
        context.localizedFallbackTitle = ""
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            return .success
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel: return .cancelled
            case .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout: return .unavailable
            default: return .failed
            }
        } catch {
            return .failed
        }
    }
}
