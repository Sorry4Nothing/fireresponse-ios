import Foundation
import os
import Testing
@testable import FireResponse

/// Eigener Stub, damit die Tests dieser Datei nicht mit den globalen `FlowStub`-Tests der anderen Dateien kollidieren.
private nonisolated final class FlowStub: URLProtocol, @unchecked Sendable {
    private struct State {
        var handler: (@Sendable (URLRequest) -> StubReply)?
        var recorded: [RecordedRequest] = []
    }
    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func install(_ handler: @escaping @Sendable (URLRequest) -> StubReply) { state.withLock { $0 = State(handler: handler) } }
    static var recorded: [RecordedRequest] { state.withLock { $0.recorded } }
    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FlowStub.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            stream.close()
        }
        let request = request
        let sent = body
        let reply = Self.state.withLock { state -> StubReply in
            state.recorded.append(RecordedRequest(request: request, body: sent))
            return state.handler?(request) ?? StubReply(500)
        }
        guard let url = request.url else { return }
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private nonisolated let unitJSON = #"{"id":"11111111-1111-1111-1111-111111111111","name":"Einheit Test","typ":"jf","bezirk":"Bezirk","rolle":"kommandant"}"#

private nonisolated func profileJSON(consented: Bool = true, mustChange: Bool = false, units: String = "[\(unitJSON)]") -> String {
    #"{"id":"u1","name":"Anna Muster","benutzername":"anna","kantonsadmin":false,"zweiterFaktor":false,"#
    + #""einwilligung":\#(consented),"mussPasswortAendern":\#(mustChange),"pushProgramme":true,"#
    + #""einheiten":\#(units),"teilnehmende":[]}"#
}

private nonisolated func sessionJSON(mustChange: Bool = false) -> String {
    #"{"user":{"id":"u1","name":"Anna Muster","username":"anna","mussPasswortAendern":\#(mustChange)}}"#
}

private nonisolated func consentJSON(valid: Bool) -> String { #"{"version":1,"text":"Text","gueltig":\#(valid)}"# }

/// Antwortet nach Pfad; unbekannte Pfade sind 404.
private func router(_ routes: [String: StubReply]) -> @Sendable (URLRequest) -> StubReply {
    { request in routes[request.url?.path ?? ""] ?? StubReply(404) }
}

@MainActor @Suite(.serialized)
struct OnboardingTests {
    func makeModel(cookie: String? = "s=1", _ routes: [String: StubReply]) -> (AppModel, InMemorySessionStore) {
        FlowStub.install(router(routes))
        let store = InMemorySessionStore(cookie: cookie)
        let client = ApiClient(baseURL: URL(string: "https://api.example.org"), appVersion: "1.0.0", store: store, configuration: FlowStub.configuration)
        return (AppModel(api: FireResponseAPI(client: client)), store)
    }

    // MARK: Phasenwahl

    @Test func withoutCookieGoesToLogin() async {
        let (model, _) = makeModel(cookie: nil, [:])
        await model.start()
        #expect(model.phase == .signedOut)
        #expect(FlowStub.recorded.isEmpty)
    }

    @Test func nullSessionGoesToLogin() async {
        let (model, store) = makeModel(["/api/auth/get-session": StubReply(200, json: "null")])
        await model.start()
        #expect(model.phase == .signedOut)
        #expect(store.read() == nil)
    }

    @Test func mustChangePasswordGoesToPasswordScreen() async {
        let (model, _) = makeModel(["/api/auth/get-session": StubReply(200, json: sessionJSON(mustChange: true))])
        await model.start()
        #expect(model.phase == .passwordChange)
        #expect(model.username == "anna")
    }

    @Test func profileFlagGoesToPasswordScreen() async {
        let (model, _) = makeModel([
            "/api/auth/get-session": StubReply(200, json: sessionJSON()),
            "/api/v1/ich": StubReply(200, json: profileJSON(mustChange: true)),
        ])
        await model.start()
        #expect(model.phase == .passwordChange)
    }

    @Test func missingConsentGoesToWelcome() async {
        let (model, _) = makeModel([
            "/api/auth/get-session": StubReply(200, json: sessionJSON()),
            "/api/v1/ich": StubReply(200, json: profileJSON(consented: false)),
            "/api/v1/einwilligung": StubReply(200, json: consentJSON(valid: false)),
        ])
        await model.start()
        #expect(model.phase == .welcome)
        #expect(model.consent?.text == "Text")
    }

    /// Neue Fassung der Einwilligung mitten in der Sitzung: Der Server antwortet mit 403, die App zeigt den Text erneut.
    @Test func newConsentVersionMidSessionShowsTheConsentAgain() async throws {
        let base: [String: StubReply] = [
            "/api/auth/get-session": StubReply(200, json: sessionJSON()),
            "/api/v1/ich": StubReply(200, json: profileJSON(consented: true)),
        ]
        let (model, _) = makeModel(base)
        // `run()` hört auf die Ereignisse des Clients, `start()` allein nicht.
        let runner = Task { await model.run() }
        defer { runner.cancel() }
        for _ in 0..<100 where model.phase != .ready { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.phase == .ready)

        FlowStub.install(router(base.merging([
            "/api/v1/ich": StubReply(200, json: profileJSON(consented: false)),
            "/api/v1/einwilligung": StubReply(200, json: consentJSON(valid: false)),
            "/api/v1/programme": StubReply(403, json: #"{"code":"EINWILLIGUNG_FEHLT"}"#),
        ]) { $1 }))
        let day = try #require(SwissDay("2027-03-01"))
        _ = await model.api.programs(from: day, to: day)
        for _ in 0..<100 where model.phase != .welcome { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.phase == .welcome)
        #expect(model.consent?.text == "Text")
    }

    @Test func consentAlreadyValidElsewhereGoesToReady() async {
        let (model, _) = makeModel([
            "/api/auth/get-session": StubReply(200, json: sessionJSON()),
            "/api/v1/ich": StubReply(200, json: profileJSON(consented: false)),
            "/api/v1/einwilligung": StubReply(200, json: consentJSON(valid: true)),
        ])
        await model.start()
        #expect(model.phase == .ready)
    }

    @Test func consentedAccountGoesToReady() async {
        let (model, _) = makeModel([
            "/api/auth/get-session": StubReply(200, json: sessionJSON()),
            "/api/v1/ich": StubReply(200, json: profileJSON()),
        ])
        await model.start()
        #expect(model.phase == .ready)
        #expect(model.profile?.name == "Anna Muster")
    }

    @Test func accountWithoutUnitShowsNoUnit() async {
        let (model, _) = makeModel([
            "/api/auth/get-session": StubReply(200, json: sessionJSON()),
            "/api/v1/ich": StubReply(200, json: profileJSON(units: "[]")),
        ])
        await model.start()
        #expect(model.phase == .noUnit)
    }

    @Test func expiredSessionShowsSessionExpiredAndClearsCookie() async {
        let (model, store) = makeModel(["/api/auth/get-session": StubReply(401)])
        await model.start()
        #expect(model.phase == .sessionExpired)
        #expect(store.read() == nil)
        model.backToLogin()
        #expect(model.phase == .signedOut)
    }

    @Test func offlineStartKeepsSessionAndShowsError() async {
        FlowStub.install { _ in .failing(.notConnectedToInternet) }
        let store = InMemorySessionStore(cookie: "s=1")
        let client = ApiClient(baseURL: URL(string: "https://api.example.org"), appVersion: "1", store: store, configuration: FlowStub.configuration)
        let model = AppModel(api: FireResponseAPI(client: client))
        await model.start()
        #expect(model.phase == .launching)
        #expect(model.startError == .offline)
        #expect(store.read() == "s=1")
    }

    @Test func outdatedAppShowsHint() async {
        let (model, _) = makeModel(["/api/auth/get-session": StubReply(426)])
        await model.start()
        #expect(model.startError == .appOutdated)
    }

    // MARK: Anmelden und Passwort

    @Test func wrongCredentialsAreFriendlyAndRepeatedHintComesAtThree() async {
        let (model, _) = makeModel(cookie: nil, ["/api/auth/sign-in/username": StubReply(401)])
        #expect(await model.signIn(username: "anna", password: "x") == .invalidCredentials(repeated: false))
        #expect(await model.signIn(username: "anna", password: "x") == .invalidCredentials(repeated: false))
        #expect(await model.signIn(username: "anna", password: "x") == .invalidCredentials(repeated: true))
    }

    @Test func tooManyRequestsCarriesWaitTime() async {
        let (model, _) = makeModel(cookie: nil, ["/api/auth/sign-in/username": StubReply(429, headers: ["X-Retry-After": "120"])])
        #expect(await model.signIn(username: "anna", password: "x") == .tooManyRequests(waitSeconds: 120))
    }

    @Test func secondFactorIsRefusedWithoutSession() async {
        let (model, store) = makeModel(cookie: "two_factor=1", ["/api/auth/sign-in/username": StubReply(200, json: #"{"twoFactorRedirect":true}"#)])
        #expect(await model.signIn(username: "admin", password: "x") == .adminOnly)
        #expect(store.read() == nil)
    }

    @Test func signInThenPasswordChangeUsesRememberedStartPassword() async throws {
        let changed = OSAllocatedUnfairLock(initialState: false)
        let (model, _) = makeModel(cookie: nil, [:])
        FlowStub.install { request in
            switch request.url?.path {
            case "/api/auth/sign-in/username": StubReply(200, json: #"{"user":{"id":"u1","name":"Anna","mussPasswortAendern":true}}"#)
            case "/api/auth/get-session": StubReply(200, json: sessionJSON(mustChange: !changed.withLock { $0 }))
            case "/api/auth/change-password":
                { changed.withLock { $0 = true }; return StubReply(200, json: "{}") }()
            case "/api/v1/ich": StubReply(200, json: profileJSON(consented: true))
            default: StubReply(404)
            }
        }
        #expect(await model.signIn(username: " anna ", password: "start-pass") == nil)
        #expect(model.phase == .passwordChange)
        #expect(model.knowsStartPassword)
        #expect(await model.changePassword(current: nil, new: "ein-langes-eigenes-passwort") == nil)
        #expect(model.phase == .ready)
        #expect(!model.knowsStartPassword)
        let signIn = try #require(FlowStub.recorded.first)
        #expect((String(bytes: signIn.body, encoding: .utf8) ?? "").contains(#""username":"anna""#))
        let change = try #require(FlowStub.recorded.first { $0.request.url?.path == "/api/auth/change-password" })
        #expect((String(bytes: change.body, encoding: .utf8) ?? "").contains(#""currentPassword":"start-pass""#))
    }

    @Test func passwordErrorCodesMapToFriendlyCases() {
        func map(_ code: String) -> FormError { .password(code: code, error: .unknown, retryAfterSeconds: nil) }
        #expect(map("PASSWORD_COMPROMISED") == .passwordCompromised)
        #expect(map("PASSWORD_TOO_SHORT") == .passwordTooShort)
        #expect(map("PASSWORD_TOO_LONG") == .passwordTooLong)
        #expect(map("PASSWORT_UNVERAENDERT") == .passwordUnchanged)
        #expect(map("INVALID_PASSWORD") == .currentPasswordWrong)
        #expect(map("SOMETHING_ELSE") == .unknown)
        #expect(FormError.password(code: nil, error: .network, retryAfterSeconds: nil) == .offline)
    }

    @Test func wrongStartPasswordForgetsIt() async {
        let (model, _) = makeModel(cookie: nil, [
            "/api/auth/sign-in/username": StubReply(200, json: #"{"user":{"id":"u1","name":"Anna","mussPasswortAendern":true}}"#),
            "/api/auth/get-session": StubReply(200, json: sessionJSON(mustChange: true)),
            "/api/auth/change-password": StubReply(400, json: #"{"code":"INVALID_PASSWORD","message":"English server text"}"#),
        ])
        _ = await model.signIn(username: "anna", password: "alt")
        #expect(await model.changePassword(current: nil, new: "ein-langes-eigenes-passwort") == .currentPasswordWrong)
        #expect(!model.knowsStartPassword)
    }

    @Test func consentGivenLeadsToReady() async {
        let (model, _) = makeModel([
            "/api/auth/get-session": StubReply(200, json: sessionJSON()),
            "/api/v1/ich": StubReply(200, json: profileJSON(consented: false)),
            "/api/v1/einwilligung": StubReply(200, json: consentJSON(valid: false)),
        ])
        await model.start()
        FlowStub.install(router([
            "/api/auth/get-session": StubReply(200, json: sessionJSON()),
            "/api/v1/ich": StubReply(200, json: profileJSON(consented: true)),
            "/api/v1/einwilligung": StubReply(204),
        ]))
        #expect(await model.acceptConsent() == nil)
        #expect(model.phase == .ready)
        #expect(FlowStub.recorded.first?.request.httpMethod == "PUT")
    }

    // MARK: Abmelden

    @Test func signOutClearsEverything() async {
        let (model, store) = makeModel([
            "/api/auth/get-session": StubReply(200, json: sessionJSON()),
            "/api/v1/ich": StubReply(200, json: profileJSON()),
            "/api/auth/sign-out": StubReply(200, json: "{}"),
        ])
        await model.start()
        #expect(model.phase == .ready)
        await model.signOut()
        #expect(model.phase == .signedOut)
        #expect(model.profile == nil)
        #expect(model.username == nil)
        #expect(store.read() == nil)
        #expect(!model.isBusy)
    }

    @Test func signOutWorksOfflineToo() async {
        FlowStub.install { _ in .failing(.notConnectedToInternet) }
        let store = InMemorySessionStore(cookie: "s=1")
        let client = ApiClient(baseURL: URL(string: "https://api.example.org"), appVersion: "1", store: store, configuration: FlowStub.configuration)
        let model = AppModel(api: FireResponseAPI(client: client))
        await model.signOut()
        #expect(model.phase == .signedOut)
        #expect(store.read() == nil)
    }

    @Test func noUnitSignOutLeavesNoSession() async {
        let (model, store) = makeModel([
            "/api/auth/get-session": StubReply(200, json: sessionJSON()),
            "/api/v1/ich": StubReply(200, json: profileJSON(units: "[]")),
            "/api/auth/sign-out": StubReply(204),
        ])
        await model.start()
        #expect(model.phase == .noUnit)
        await model.signOut()
        #expect(model.phase == .signedOut)
        #expect(store.read() == nil)
    }
}

struct PasswordRulesTests {
    @Test func rules() {
        func rules(_ new: String, repeated: String = "", current: String = "start", username: String? = "anna") -> PasswordRules {
            PasswordRules(new: new, repeated: repeated, current: current, username: username)
        }
        #expect(!rules("kurz").longEnough)
        #expect(rules("zwoelf-zeichen").longEnough)
        #expect(!rules("ANNA").notUsername)
        #expect(!rules("start").notStartPassword)
        #expect(!rules("").allMet)
        #expect(rules("ein-langes-passwort", repeated: "ein-langes-passwort").canSave)
        #expect(!rules("ein-langes-passwort", repeated: "anders").canSave)
    }

    @Test func waitText() {
        #expect(FormError.waitText(0) == "1 Sekunde")
        #expect(FormError.waitText(45) == "45 Sekunden")
        #expect(FormError.waitText(90) == "90 Sekunden")
        #expect(FormError.waitText(91) == "2 Minuten")
        #expect(FormError.waitText(900) == "15 Minuten")
    }
}

@MainActor @Suite(.serialized)
struct MaintenanceTests {
    private func makeModel(_ routes: [String: StubReply]) -> AppModel {
        FlowStub.install(router(routes))
        let store = InMemorySessionStore(cookie: "s=1")
        let client = ApiClient(baseURL: URL(string: "https://api.example.org"), appVersion: "1.0.0", store: store, configuration: FlowStub.configuration)
        return AppModel(api: FireResponseAPI(client: client))
    }

    @Test func standardTextWithoutEndAndWithEnd() throws {
        let now = try #require(Date.fromAPI("2026-11-13T12:00:00+01:00"))
        let same = try #require(Date.fromAPI("2026-11-13T22:00:00+01:00"))
        let later = try #require(Date.fromAPI("2026-11-14T08:00:00+01:00"))
        #expect(MaintenanceText.message(for: MaintenanceInfo(text: nil, until: nil), now: now)
            == "FireResponse wird gerade gewartet. Bitte versuche es später noch einmal.")
        #expect(MaintenanceText.message(for: MaintenanceInfo(text: nil, until: same), now: now)
            == "FireResponse wird gerade gewartet, voraussichtlich bis 22:00 Uhr. Deine Zusagen bleiben gespeichert.")
        #expect(MaintenanceText.message(for: MaintenanceInfo(text: nil, until: later), now: now).contains("Samstag, 14. November, 08:00 Uhr"))
    }

    @Test func operatorTextWinsAndIsLimited() throws {
        let now = try #require(Date.fromAPI("2026-11-13T12:00:00+01:00"))
        #expect(MaintenanceText.message(for: MaintenanceInfo(text: "  Update läuft.  ", until: nil), now: now) == "Update läuft.")
        #expect(MaintenanceInfo(text: String(repeating: "a", count: 400), until: nil).text?.count == MaintenanceInfo.maxTextLength)
        #expect(MaintenanceInfo(text: "   ", until: nil).text == nil)
    }

    @Test func recheckClearsTheMaintenanceAndKeepsItWhileActive() async {
        let model = makeModel(["/api/v1/wartung": StubReply(200, json: #"{"aktiv":true,"text":null,"ende":null,"seit":null}"#)])
        await model.recheckMaintenance()
        #expect(model.maintenance == MaintenanceInfo(text: nil, until: nil) && model.maintenanceCheck == .stillOn)

        FlowStub.install(router(["/api/v1/wartung": StubReply(200, json: #"{"aktiv":false,"text":null,"ende":null,"seit":null}"#)]))
        await model.recheckMaintenance()
        #expect(model.maintenance == nil && model.maintenanceCheck == .idle && model.maintenanceEnded == 1)
    }

    @Test func recheckWithoutNetworkKeepsTheScreen() async {
        let model = makeModel([:]) // unbekannter Pfad: 404
        await model.recheckMaintenance()
        #expect(model.maintenanceCheck == .offline)
    }
}
