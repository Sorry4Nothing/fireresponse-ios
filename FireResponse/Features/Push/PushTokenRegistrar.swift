import Foundation

/// Hinterlegt das FCM-Token beim Server: nur mit Sitzung, nur bei einem neuen Token oder nach neuem Login (der Server
/// löscht das Token mit der Sitzung). Das Token wird nie geloggt oder angezeigt.
@MainActor
final class PushTokenRegistrar {
    typealias Register = @MainActor (String) async -> ApiResult<Void>

    private let register: Register
    private var token: String?
    private var signedIn = false
    private var registered: String?
    private var inFlight: String?

    init(register: @escaping Register) {
        self.register = register
    }

    /// Der Server verlangt 20 bis 512 Zeichen aus Buchstaben, Ziffern und `_ : . -`.
    static func isValid(_ token: String) -> Bool {
        (20...512).contains(token.utf8.count) && token.utf8.allSatisfy { $0.isASCIIAlnum || "_:.-".utf8.contains($0) }
    }

    func setToken(_ newToken: String?) async {
        token = newToken
        await syncIfNeeded()
    }

    func setSignedIn(_ value: Bool) async {
        if !value { registered = nil }
        signedIn = value
        await syncIfNeeded()
    }

    private func syncIfNeeded() async {
        guard signedIn, let token, Self.isValid(token), token != registered, token != inFlight else { return }
        inFlight = token
        defer { inFlight = nil }
        // shortcut: bei Fehler kein eigener Wiederholversuch, der nächste Start, Login oder Tokenwechsel holt es nach.
        if case .ok = await register(token), signedIn, self.token == token { registered = token }
    }
}

private extension UInt8 {
    var isASCIIAlnum: Bool { (48...57).contains(self) || (65...90).contains(self) || (97...122).contains(self) }
}
