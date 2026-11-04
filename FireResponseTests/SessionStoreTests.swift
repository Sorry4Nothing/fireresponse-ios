import Foundation
import Security
import Testing
@testable import FireResponse

/// Ohne Signierung (CI mit `CODE_SIGNING_ALLOWED=NO`) hat der Test-Host keinen Zugriff auf die Keychain (OSStatus -34018);
/// dann entfallen die beiden Keychain-Tests. Lokal mit Signierung laufen sie.
private nonisolated let keychainAvailable: Bool = {
    let store = KeychainSessionStore(service: "ch.fireresponse.test.probe.\(UUID().uuidString)")
    defer { store.clear() }
    store.write("probe")
    return store.read() == "probe"
}()

@Suite(.serialized)
struct SessionStoreTests {
    @Test func inMemoryStoreRoundTrip() {
        let store = InMemorySessionStore()
        store.write("a=1")
        #expect(store.read() == "a=1")
        store.clear()
        #expect(store.read() == nil)
    }

    @Test(.enabled(if: keychainAvailable, "Keychain ohne Signierung nicht verfügbar"))
    func keychainStoreWritesReplacesAndClears() throws {
        let store = KeychainSessionStore(service: "ch.fireresponse.test.\(UUID().uuidString)")
        defer { store.clear() }
        store.write("a=1")
        #expect(store.read() == "a=1")
        store.write("a=2; b=3")
        #expect(store.read() == "a=2; b=3")
        store.clear()
        #expect(store.read() == nil)
    }

    @Test(.enabled(if: keychainAvailable, "Keychain ohne Signierung nicht verfügbar"))
    func keychainItemIsThisDeviceOnly() throws {
        let service = "ch.fireresponse.test.\(UUID().uuidString)"
        let store = KeychainSessionStore(service: service)
        defer { store.clear() }
        store.write("a=1")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess)
        let attributes = try #require(item as? [String: Any])
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }
}
