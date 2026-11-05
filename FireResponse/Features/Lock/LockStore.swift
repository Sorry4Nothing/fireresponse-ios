import Foundation
import Security

/// Ort der Sperr-Einstellung. Ein Eintrag heisst: Sperre an; der Inhalt ist der Stand der Biometrie bei der Einrichtung.
/// In der Keychain statt `UserDefaults`, damit sich die Sperre nicht ohne Weiteres ausschalten lässt (SR Sessions).
nonisolated protocol LockStore: Sendable {
    func read() -> Data?
    func write(_ baseline: Data)
    func clear()
}

/// Keychain, nur bei entsperrtem Gerät und nie auf ein anderes Gerät.
nonisolated struct KeychainLockStore: LockStore {
    let service: String

    init(service: String = "ch.fireresponse.app.lock") {
        self.service = service
    }

    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "baseline"]
    }

    func read() -> Data? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    func write(_ baseline: Data) {
        if SecItemUpdate(identity as CFDictionary, [kSecValueData as String: baseline] as CFDictionary) == errSecSuccess { return }
        var attributes = identity
        attributes[kSecValueData as String] = baseline
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(identity as CFDictionary)
    }
}
