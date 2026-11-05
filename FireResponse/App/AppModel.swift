import Foundation
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

    /// Text der Einwilligung für Willkommen (vom Server, `GET /einwilligung`).
    private(set) var consent: Consent?
    /// Der Start kam nicht bis zu einer Phase (offline, App zu alt, …): `.launching` zeigt dann den Fehler mit «Nochmals versuchen».
    private(set) var startError: FormError?
    /// Globale Ladesperre: Solange eine Aktion läuft, nimmt der Start-Ablauf keine zweite an und sperrt die Bedienung.
    private(set) var isBusy = false
    /// Das Passwort wurde eben gespeichert (Hinweis auf Willkommen).
    private(set) var passwordJustSaved = false
    /// Benutzername des Kontos (aus der Sitzung oder dem Profil), für die Regel «nicht dein Benutzername».
    private(set) var username: String?
    /// Ob das Startpasswort vom Login noch im Arbeitsspeicher liegt. Sonst fragt der Passwort-Screen danach.
    private(set) var knowsStartPassword = false

    /// Das Passwort des Logins, nur im Arbeitsspeicher und nur bis der Pflichtwechsel durch ist: Der Server verlangt zum Ändern
    /// das bisherige Passwort. Nie in Logs, Zustandswiederherstellung oder auf dem Gerät.
    private var startPassword: String? {
        didSet { knowsStartPassword = startPassword != nil }
    }
    private var failedSignIns = 0
    private var rechecking = false

    /// Ab so vielen Fehlversuchen in Folge sagt die Meldung, dass der Server das Konto sperren kann.
    static let repeatedFailureThreshold = 3

    init(api: FireResponseAPI) {
        self.api = api
    }

    // MARK: Ablauf

    /// Startet die App: Ablauf prüfen und danach auf Ereignisse des Clients hören (läuft, solange die App läuft).
    func run() async {
        await start()
        for await event in api.client.events {
            switch event {
            case .unauthorized: if phase != .signedOut { await leave(expired: true) }
            case .forbidden: await recheckAfterForbidden()
            }
        }
    }

    /// Fragt Sitzung und Profil und wählt die Phase. Auch für «Nochmals versuchen».
    func start() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        startError = nil
        phase = .launching
        guard await api.client.hasSession() else { return phase = .signedOut }
        await resolve()
    }

    /// Meldet an. `nil`: weiter mit der Phase, die der Server vorgibt; sonst der Fehler für das Formular.
    func signIn(username: String, password: String) async -> FormError? {
        guard !isBusy else { return nil }
        isBusy = true
        defer { isBusy = false }
        switch await api.signIn(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password) {
        case .failure(let error, _, let retry):
            guard error == .notSignedIn else { return .from(error, retryAfterSeconds: retry) }
            failedSignIns += 1
            return .invalidCredentials(repeated: failedSignIns >= Self.repeatedFailureThreshold)
        case .ok(let response):
            // Der zweite Faktor gilt nur im Admin-Bereich: Es gibt keine Sitzung, auch kein halbes Cookie.
            if response.needsSecondFactor {
                await api.client.forgetSession()
                return .adminOnly
            }
            failedSignIns = 0
            startPassword = password
            await resolve()
            if phase != .passwordChange { startPassword = nil }
            return nil
        }
    }

    /// Speichert das eigene Passwort. `current`: Startpasswort, wenn die App es nicht mehr kennt.
    func changePassword(current: String?, new: String) async -> FormError? {
        guard !isBusy, let old = startPassword ?? current else { return nil }
        isBusy = true
        defer { isBusy = false }
        switch await api.changePassword(current: old, new: new) {
        case .failure(.notSignedIn, _, _):
            await leave(expired: true)
            return nil
        case .failure(let error, let code, let retry):
            // Stimmt das Startpasswort nicht, fragt der Screen danach, statt dasselbe nochmals zu senden.
            if code == "INVALID_PASSWORD" { startPassword = nil }
            return .password(code: code, error: error, retryAfterSeconds: retry)
        case .ok:
            startPassword = nil
            passwordJustSaved = true
            await resolve()
            return nil
        }
    }

    /// Einwilligung geben (`PUT /einwilligung`); danach prüft der Ablauf die Phase erneut.
    func acceptConsent() async -> FormError? {
        guard !isBusy, phase == .welcome else { return nil }
        isBusy = true
        defer { isBusy = false }
        switch await api.giveConsent() {
        case .failure(.notSignedIn, _, _):
            await leave(expired: true)
            return nil
        case .failure(let error, _, let retry):
            return .from(error, retryAfterSeconds: retry)
        case .ok:
            passwordJustSaved = false
            await resolve()
            return nil
        }
    }

    /// Beendet die Sitzung auf dem Server und leert alles auf dem Gerät. Offline geht es auch: Dann endet sie dort mit ihrem Ablauf.
    func signOut() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        _ = await api.signOut()
        await leave(expired: false)
    }

    /// Von «Sitzung abgelaufen» zum Login.
    func backToLogin() {
        phase = .signedOut
    }

    /// Lädt das Profil neu (z. B. nach einem neuen Profilbild). `false`, wenn es nicht klappt; bei beendeter Sitzung geht es zum Login.
    @discardableResult
    func reloadProfile() async -> Bool {
        switch await api.me() {
        case .ok(let fresh):
            profile = fresh
            return true
        case .failure(.notSignedIn, _, _):
            await leave(expired: true)
            return false
        case .failure:
            return false
        }
    }

    // MARK: Phasenwahl

    /// Sitzung, Profil und Einwilligung prüfen und die Phase setzen. Scheitert eine Antwort, bleibt es bei `.launching` mit `startError`.
    private func resolve() async {
        switch await api.session() {
        case .failure(let error, _, let retry): await fail(error, retry)
        case .ok(nil): await leave(expired: false)
        case .ok(let session?):
            username = session.user.username
            if session.user.mustChangePassword { phase = .passwordChange } else { await loadProfile() }
        }
    }

    private func loadProfile() async {
        switch await api.me() {
        case .failure(let error, _, let retry): await fail(error, retry)
        case .ok(let fresh):
            profile = fresh
            username = fresh.username
            if fresh.mustChangePassword {
                phase = .passwordChange
            } else if fresh.units.isEmpty && fresh.participants.isEmpty {
                phase = .noUnit
            } else if !fresh.hasConsented {
                await askConsent()
            } else {
                enterReady()
            }
        }
    }

    /// Holt den Text der aktuellen Einwilligung; gilt sie schon (anderes Gerät), geht es weiter.
    private func askConsent() async {
        switch await api.consent() {
        case .failure(let error, _, let retry): await fail(error, retry)
        case .ok(let current):
            if current.isValid {
                enterReady()
            } else {
                consent = current
                phase = .welcome
            }
        }
    }

    private func enterReady() {
        consent = nil
        startError = nil
        phase = .ready
    }

    private func fail(_ error: ApiError, _ retry: Int?) async {
        if error == .notSignedIn {
            await leave(expired: true)
        } else {
            startError = .from(error, retryAfterSeconds: retry)
            phase = .launching
        }
    }

    /// Ein 403 unter `/api/v1` heisst auch «Passwortwechsel offen» oder «Einwilligung fehlt». `GET /ich` bleibt dann erreichbar
    /// und sagt es. Mehrere 403 gleichzeitig prüfen einmal.
    private func recheckAfterForbidden() async {
        guard phase == .ready, !rechecking else { return }
        rechecking = true
        defer { rechecking = false }
        guard case .ok(let fresh) = await api.me() else { return }
        if fresh.mustChangePassword {
            profile = fresh
            phase = .passwordChange
        } else if !fresh.hasConsented {
            profile = fresh
            await askConsent()
        }
    }

    // MARK: Abmelden

    /// Verlässt die Sitzung: Cookie in der Keychain, Profil, Caches und Passwörter im Arbeitsspeicher sind weg.
    private func leave(expired: Bool) async {
        startPassword = nil
        profile = nil
        consent = nil
        username = nil
        startError = nil
        passwordJustSaved = false
        failedSignIns = 0
        URLCache.shared.removeAllCachedResponses()
        WidgetSync.clear()
        await api.client.forgetSession()
        phase = expired ? .sessionExpired : .signedOut
    }
}
