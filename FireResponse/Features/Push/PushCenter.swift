import FirebaseCore
import FirebaseMessaging
import Observation
import UIKit
import UserNotifications

/// Der eine Ort für Push: Firebase, Erlaubnis des Systems und Token. Ohne `GoogleService-Info.plist` im Bundle
/// bleibt alles aus, die App läuft dann ohne Push.
///
/// Anbindung (Integrationsschritt): `.pushRegistration()` einmal am Wurzel-View, `PushCenter.shared.router` an die Übungsliste.
@MainActor @Observable
final class PushCenter {
    static let shared = PushCenter()

    let router = PushRouter()
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var isFirebaseConfigured = false

    @ObservationIgnored private var api: FireResponseAPI?
    @ObservationIgnored private var registrar: PushTokenRegistrar?

    private init() {
        registrar = PushTokenRegistrar { [weak self] token in
            guard let api = self?.api else { return .failure(.notSignedIn) }
            return await api.registerPushToken(token)
        }
    }

    /// Beim Start der App. Firebase startet nur mit Konfigurationsdatei; die Token-Anfrage folgt erst nach dem Login.
    func start(messagingDelegate: any MessagingDelegate) {
        guard !isFirebaseConfigured, Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return }
        FirebaseApp.configure()
        Messaging.messaging().delegate = messagingDelegate
        isFirebaseConfigured = true
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Fragt das System nach der Erlaubnis. Nur im richtigen Moment aufrufen (nach dem Willkommen, in den Einstellungen).
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refreshAuthorization()
        await registerWithSystemIfAllowed()
    }

    /// Login und Abmelden: Mit Sitzung holt die App das Token (wenn die Person Mitteilungen erlaubt hat) und hinterlegt es.
    func sessionChanged(api: FireResponseAPI, signedIn: Bool) async {
        self.api = api
        await registrar?.setSignedIn(signedIn)
        guard signedIn else { return }
        await refreshAuthorization()
        await registerWithSystemIfAllowed()
    }

    func tokenReceived(_ token: String?) async {
        await registrar?.setToken(token)
    }

    private func registerWithSystemIfAllowed() async {
        guard isFirebaseConfigured, authorization == .authorized || authorization == .provisional else { return }
        // Erst nach dem Login: Vorher soll Firebase kein Token holen (Info.plist: FirebaseMessagingAutoInitEnabled = NO).
        Messaging.messaging().isAutoInitEnabled = true
        UIApplication.shared.registerForRemoteNotifications()
        // Das Token kommt über `messaging(_:didReceiveRegistrationToken:)` im `PushAppDelegate` (jetzt, wo Auto-Init an ist, und bei jeder
        // Erneuerung). `token()` ist veraltet; sein Ersatz `register(completion:)` liefert eine Installations-ID und gehört zu einem Wechsel,
        // den das Backend mitmachen müsste.
    }
}
