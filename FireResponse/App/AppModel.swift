import Observation

/// Zustand der App über alle Screens. `phase` und `profile` pflegt der Start-Ablauf (Login, Passwort, Willkommen);
/// die Tabs lesen nur `api` und `profile`.
@MainActor @Observable
final class AppModel {
    enum Phase: Equatable {
        case launching, signedOut, sessionExpired, passwordChange, welcome, noUnit, ready
    }

    let api: FireResponseAPI
    var phase: Phase = .launching
    var profile: Profile?

    init(api: FireResponseAPI) {
        self.api = api
    }
}
