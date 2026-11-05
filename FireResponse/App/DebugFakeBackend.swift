#if DEBUG
// Nur für Debug mit erfundenen Antworten: lange JSON-Zeilen und eine grosse Weiche sind hier bewusst.
// swiftlint:disable line_length cyclomatic_complexity
import Foundation
import os

/// Fake-Backend zum Ausprobieren ohne Server. Läuft nur im Debug-Build und nur auf ausdrücklichen Launch-Parameter
/// `-FireResponseFakeBackend` (optional `-FireResponseFakeLogin <konto>` setzt die Sitzung dieses Kontos).
/// Erfundene Konten, alle mit Startpasswort `startpasswort123`: `demo` (Elternteil von Lena und Noah, muss das Passwort ändern),
/// `eltern` (Passwort schon gewählt, Einwilligung offen), `kommando` (Kommandantin, alles erledigt), `leer` (Konto ohne Einheit).
/// Der Stand liegt im Arbeitsspeicher.
enum DebugFakeBackend {
    static let launchArgument = "-FireResponseFakeBackend"
    static let loginArgument = "-FireResponseFakeLogin"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    static func makeClient() -> ApiClient {
        let arguments = ProcessInfo.processInfo.arguments
        let login = arguments.firstIndex(of: loginArgument).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        let store = MemoryStore(cookie: login.map { "fr_fake=\($0)" })
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeBackendProtocol.self]
        return ApiClient(baseURL: URL(string: "https://fake.fireresponse.invalid"), appVersion: "0.0.0", store: store, configuration: configuration)
    }

    private nonisolated final class MemoryStore: SessionStore {
        private let cookie: OSAllocatedUnfairLock<String?>
        init(cookie: String?) { self.cookie = .init(initialState: cookie) }
        func read() -> String? { cookie.withLock { $0 } }
        func write(_ value: String) { cookie.withLock { $0 = value } }
        func clear() { cookie.withLock { $0 = nil } }
    }
}

private nonisolated struct FakeAccount {
    var password = "startpasswort123"
    var mustChangePassword: Bool
    var consented: Bool
    let name: String
    let hasUnit: Bool
    let isParent: Bool
}

private nonisolated final class FakeBackendProtocol: URLProtocol, @unchecked Sendable {
    private static let accounts = OSAllocatedUnfairLock<[String: FakeAccount]>(initialState: [
        "demo": FakeAccount(mustChangePassword: true, consented: false, name: "Petra Beispiel", hasUnit: true, isParent: true),
        "eltern": FakeAccount(mustChangePassword: false, consented: false, name: "Petra Beispiel", hasUnit: true, isParent: true),
        "kommando": FakeAccount(mustChangePassword: false, consented: true, name: "Karin Kommando", hasUnit: true, isParent: false),
        "leer": FakeAccount(mustChangePassword: false, consented: true, name: "Lea Leer", hasUnit: false, isParent: false),
    ])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let (status, json, headers) = respond()
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private var body: [String: Any] {
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Konto der Sitzung (Cookie `fr_fake=<konto>`), wenn es existiert.
    private var sessionUser: String? {
        let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
        let name = cookie.components(separatedBy: "; ").first { $0.hasPrefix("fr_fake=") }.map { String($0.dropFirst(8)) }
        guard let name, Self.accounts.withLock({ $0[name] }) != nil else { return nil }
        return name
    }

    private func respond() -> (Int, String, [String: String]) {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        switch (method, path) {
        case (Endpoint.signIn.method.rawValue, Endpoint.signIn.template):
            let input = body
            let name = (input["username"] as? String ?? "").lowercased()
            let password = input["password"] as? String ?? ""
            let known = Self.accounts.withLock { $0[name] }
            guard let known, known.password == password else { return (401, #"{"code":"INVALID_USERNAME_OR_PASSWORD"}"#, [:]) }
            return (200, #"{"user":\#(userJSON(name, known))}"#, ["Set-Cookie": "fr_fake=\(name); Path=/"])
        case (Endpoint.signOut.method.rawValue, Endpoint.signOut.template):
            return (200, "{}", ["Set-Cookie": "fr_fake=; Max-Age=0; Path=/"])
        default: break
        }
        guard let user = sessionUser, let account = Self.accounts.withLock({ $0[user] }) else {
            return path == Endpoint.session.template ? (200, "null", [:])
                : path == Endpoint.privacy.template ? (200, privacyJSON, [:]) : (401, "{}", [:])
        }
        switch (method, path) {
        case (Endpoint.session.method.rawValue, Endpoint.session.template):
            return (200, #"{"user":\#(userJSON(user, account))}"#, [:])
        case (Endpoint.changePassword.method.rawValue, Endpoint.changePassword.template):
            let input = body
            let new = input["newPassword"] as? String ?? ""
            if input["currentPassword"] as? String != account.password { return (400, #"{"code":"INVALID_PASSWORD"}"#, [:]) }
            if new == account.password { return (400, #"{"code":"PASSWORT_UNVERAENDERT"}"#, [:]) }
            if new.count < 12 { return (400, #"{"code":"PASSWORD_TOO_SHORT"}"#, [:]) }
            if new.lowercased().contains("password") || new.lowercased().contains("passwort123") { return (400, #"{"code":"PASSWORD_COMPROMISED"}"#, [:]) }
            Self.accounts.withLock { $0[user]?.password = new; $0[user]?.mustChangePassword = false }
            return (200, "{}", [:])
        case (Endpoint.me.method.rawValue, Endpoint.me.template):
            return (200, profileJSON(user, account), [:])
        case (Endpoint.consent.method.rawValue, Endpoint.consent.template):
            return (200, #"{"version":1,"text":"Ich bin damit einverstanden, dass FireResponse meinen Namen und die Zusagen meiner Kinder für die Einheit speichert. Nur die Leitung meiner Einheit sieht sie. Ich kann das jederzeit bei der Leitung widerrufen.","gueltig":\#(account.consented)}"#, [:])
        case (Endpoint.giveConsent.method.rawValue, Endpoint.giveConsent.template):
            Self.accounts.withLock { $0[user]?.consented = true }
            return (204, "", [:])
        case (Endpoint.privacy.method.rawValue, Endpoint.privacy.template):
            return (200, privacyJSON, [:])
        case (Endpoint.programs.method.rawValue, Endpoint.programs.template):
            return (200, #"{"programme":[]}"#, [:])
        default:
            return (404, "{}", [:])
        }
    }

    private func userJSON(_ username: String, _ account: FakeAccount) -> String {
        #"{"id":"u-\#(username)","name":"\#(account.name)","username":"\#(username)","role":"user","mussPasswortAendern":\#(account.mustChangePassword)}"#
    }

    private func profileJSON(_ username: String, _ account: FakeAccount) -> String {
        let unit = #"{"id":"11111111-1111-1111-1111-111111111111","name":"Kinder- und Jugendfeuerwehr Beispielstadt","typ":"kf","bezirk":"Beispielbezirk","rolle":"kommandant"}"#
        let children = #"[{"id":"c1","vorname":"Lena","nachname":"Beispiel","einheitId":"11111111-1111-1111-1111-111111111111","art":"eltern","abzeichen":{"kuerzel":"R2","sterne":2}},{"id":"c2","vorname":"Noah","nachname":"Beispiel","einheitId":"11111111-1111-1111-1111-111111111111","art":"eltern","abzeichen":{"kuerzel":"R1","sterne":1}}]"#
        let units = account.hasUnit && !account.isParent ? "[\(unit)]" : "[]"
        let participants = account.hasUnit && account.isParent ? children : "[]"
        return #"{"id":"u-\#(username)","name":"\#(account.name)","benutzername":"\#(username)","kantonsadmin":false,"zweiterFaktor":false,"einwilligung":\#(account.consented),"mussPasswortAendern":\#(account.mustChangePassword),"pushProgramme":true,"einheiten":\#(units),"teilnehmende":\#(participants)}"#
    }

    private var privacyJSON: String {
        #"{"version":1,"abschnitte":[{"titel":"Was wir speichern","text":"Wir speichern deinen Namen, deine Zusagen und, wenn du es willst, dein Profilbild.\n\n– Keine Werbung\n\n– Keine Tracker"},{"titel":"Wer was sieht","text":"Dein Konto gehört zu genau einer Einheit. Nur die Leitung dieser Einheit sieht deine Zusagen."},{"titel":"Löschen","text":"Frag deine Leitung, wenn du deine Daten löschen lassen willst."}]}"#
    }
}
// swiftlint:enable line_length cyclomatic_complexity
#endif
