import FirebaseMessaging
import UIKit
import UserNotifications

/// Start von Firebase, Anzeige von Mitteilungen bei offener App und Tipp auf eine Mitteilung.
/// Die Methoden der Protokolle sind `nonisolated`; sie wechseln selbst auf den Main Actor.
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        PushCenter.shared.start(messagingDelegate: self)
        return true
    }

    /// Bei offener App zeigt das System nichts von allein: Banner und Ton, wie Android es mit `Notifications.show` tut.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let target = PushTarget.from(userInfo: response.notification.request.content.userInfo) else { return }
        await MainActor.run { PushCenter.shared.router.open(target) }
    }

    /// Firebase meldet das Token beim ersten Mal und bei jeder Erneuerung.
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in await PushCenter.shared.tokenReceived(fcmToken) }
    }
}
