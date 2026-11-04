import Foundation
import Security

/// Ort der Sitzung: das Cookie als `name=wert; name2=wert2`. Der Wert ist ein Geheimnis und wird nie geloggt.
nonisolated protocol SessionStore: Sendable {
    func read() -> String?
    func write(_ cookie: String)
    /// Löscht alles, auch ein halbes Cookie (`two_factor`). Beim Abmelden und bei 401.
    func clear()
}

/// Keychain, nur bei entsperrtem Gerät und nie auf ein anderes Gerät (kein Backup, kein iCloud).
nonisolated struct KeychainSessionStore: SessionStore {
    let service: String

    init(service: String = "ch.fireresponse.app.session") {
        self.service = service
    }

    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "cookie"]
    }

    func read() -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ cookie: String) {
        let data = Data(cookie.utf8)
        if SecItemUpdate(identity as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess { return }
        var attributes = identity
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(identity as CFDictionary)
    }
}
