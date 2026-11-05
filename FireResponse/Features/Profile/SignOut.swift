import Foundation

/// Abmelden: beendet die Sitzung (`api.signOut()` leert auch die Keychain, selbst wenn der Server nicht antwortet),
/// löscht die Sperr-Einstellung, die Caches und den Stand des Widgets und führt die App zurück zum Login. Nichts davon bleibt auf dem Gerät.
@MainActor
enum SignOut {
    static func perform(
        model: AppModel,
        lock: AppLockController,
        clearCaches: @MainActor () -> Void = { URLCache.shared.removeAllCachedResponses(); WidgetSync.clear() }
    ) async {
        _ = await model.api.signOut()
        lock.disable()
        clearCaches()
        model.profile = nil
        model.phase = .signedOut
    }
}
