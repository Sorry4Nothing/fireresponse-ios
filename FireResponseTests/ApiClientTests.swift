import Foundation
import Testing
@testable import FireResponse

@Suite(.serialized)
struct ApiClientTests {
    let base = URL(string: "https://api.example.org")
    let store = InMemorySessionStore()

    func makeClient(
        base: URL?? = nil,
        version: String = "1.2.0",
        cookie: String? = nil,
        _ handler: @escaping @Sendable (URLRequest) -> StubReply
    ) -> (ApiClient, FireResponseAPI, InMemorySessionStore) {
        StubURLProtocol.install(handler)
        let store = InMemorySessionStore(cookie: cookie)
        let client = ApiClient(baseURL: base ?? self.base, appVersion: version, store: store, configuration: StubURLProtocol.configuration)
        return (client, FireResponseAPI(client: client), store)
    }

    @Test func sendsHeadersAndCookie() async {
        let (_, api, _) = makeClient(cookie: "session=abc") { _ in StubReply(200, json: #"{"programme":[]}"#) }
        let from = SwissDay("2027-03-01") ?? SwissDay(date: .now)
        let result = await api.programs(from: from, to: from)

        #expect(result == .ok(ProgramList(programs: [])))
        let sent = StubURLProtocol.recorded.first
        #expect(sent?.header("Origin") == "fireresponse://")
        #expect(sent?.header("X-App-Version") == "1.2.0")
        #expect(sent?.header("Cookie") == "session=abc")
        #expect(sent?.request.url?.absoluteString == "https://api.example.org/api/v1/programme?von=2027-03-01&bis=2027-03-01")
        #expect(sent?.request.httpMethod == "GET")
    }

    @Test func baseURLWithPathKeepsThePath() async {
        let (_, api, _) = makeClient(base: .some(URL(string: "https://api.example.org/v/"))) { _ in StubReply(200, json: "null") }
        _ = await api.session()
        #expect(StubURLProtocol.recorded.first?.request.url?.absoluteString == "https://api.example.org/v/api/auth/get-session")
    }

    @Test func sessionWithoutLoginIsNull() async {
        let (_, api, _) = makeClient { _ in StubReply(200, json: "null") }
        #expect(await api.session() == .ok(nil))
    }

    @Test func noCookieHeaderWithoutSession() async {
        let (_, api, _) = makeClient { _ in StubReply(200, json: "null") }
        _ = await api.session()
        #expect(StubURLProtocol.recorded.first?.header("Cookie") == nil)
    }

    @Test func sendsJSONBody() async {
        let (_, api, _) = makeClient { _ in StubReply(204) }
        let result = await api.setParticipation(programId: "p1", participantId: "t1", answer: .no)

        #expect(result.value != nil)
        let sent = StubURLProtocol.recorded.first
        #expect(sent?.request.httpMethod == "PUT")
        #expect(sent?.request.url?.path == "/api/v1/programme/p1/teilnahmen/t1")
        #expect(sent?.header("Content-Type") == "application/json")
        #expect(String(data: sent?.body ?? Data(), encoding: .utf8) == #"{"status":"nein"}"#)
    }

    @Test func pushTokenCarriesPlatform() async {
        let (_, api, _) = makeClient { _ in StubReply(204) }
        _ = await api.registerPushToken("abcdefghijklmnopqrstuvwxyz")
        let body = String(data: StubURLProtocol.recorded.first?.body ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains(#""plattform":"ios""#) && body.contains(#""token":"abcdefghijklmnopqrstuvwxyz""#))
    }

    @Test func imageUploadSendsBytesWithType() async {
        let (_, api, _) = makeClient { _ in StubReply(204) }
        _ = await api.setMyImage(Data([1, 2, 3]), contentType: "image/png")
        let sent = StubURLProtocol.recorded.first
        #expect(sent?.header("Content-Type") == "image/png")
        #expect(sent?.body == Data([1, 2, 3]))
    }

    @Test(arguments: [
        (401, ApiError.notSignedIn), (403, .forbidden), (404, .notFound), (426, .appOutdated),
        (429, .tooManyRequests), (500, .unknown), (302, .unknown),
    ])
    func mapsStatus(status: Int, expected: ApiError) async {
        let (_, api, _) = makeClient { _ in StubReply(status, json: #"{"code":"X","message":"Text des Servers"}"#) }
        #expect(await api.me().error == expected)
    }

    @Test(arguments: [
        ("PROGRAMM_BEGONNEN", ApiError.appointmentStarted), ("ANMELDEFENSTER_NICHT_OFFEN", .registrationNotOpen),
        ("KEINE_ANMELDUNG", .noRegistration), ("PROGRAMM_GESCHLOSSEN", .registrationClosed), ("UNBEKANNT", .registrationClosed),
    ])
    func mapsConflictCodes(code: String, expected: ApiError) async {
        let (_, api, _) = makeClient { _ in StubReply(409, json: #"{"code":"\#(code)","message":"Text"}"#) }
        let result = await api.setLeadership(programId: "p", answer: .yes)
        #expect(result.map { _ in 0 } == .failure(expected, code: code))
    }

    @Test func passwordErrorKeepsTheServerCodeButNeverTheText() async {
        let (_, api, _) = makeClient { _ in StubReply(400, json: #"{"code":"PASSWORD_COMPROMISED","message":"Geheimer Text"}"#) }
        let result = await api.changePassword(current: "a", new: "b")
        #expect(result.map { _ in 0 } == .failure(.unknown, code: "PASSWORD_COMPROMISED"))
        #expect(!String(describing: result).contains("Geheimer Text"))
    }

    @Test func tooManyRequestsReadsWaitTime() async {
        let (_, api, _) = makeClient { _ in StubReply(429, headers: ["X-Retry-After": "42"]) }
        #expect(await api.me() == .failure(.tooManyRequests, retryAfterSeconds: 42))
    }

    @Test(arguments: [("0", 1), ("999999", 3600), ("-5", 1)])
    func waitTimeIsClamped(header: String, expected: Int) async {
        let (_, api, _) = makeClient { _ in StubReply(429, headers: ["X-Retry-After": header]) }
        #expect(await api.me() == .failure(.tooManyRequests, retryAfterSeconds: expected))
    }

    @Test func tooManyRequestsWithoutHeaderHasNoWaitTime() async {
        let (_, api, _) = makeClient { _ in StubReply(429, headers: ["X-Retry-After": "bald"]) }
        #expect(await api.me() == .failure(.tooManyRequests))
    }

    @Test func unauthorizedClearsSessionAndEmitsEvent() async {
        let (client, api, store) = makeClient(cookie: "session=abc") { _ in StubReply(401) }
        #expect(await api.me().error == .notSignedIn)
        #expect(store.read() == nil)
        var iterator = client.events.makeAsyncIterator()
        #expect(await iterator.next() == .unauthorized)
    }

    @Test func failedSignInKeepsStoreAndEmitsNothing() async {
        let (client, api, store) = makeClient(cookie: "other=1") { _ in StubReply(401, json: #"{"code":"ANMELDUNG_FEHLGESCHLAGEN"}"#) }
        #expect(await api.signIn(username: "a.b", password: "x").error == .notSignedIn)
        #expect(store.read() == "other=1")
        _ = await api.registerPushToken("abcdefghijklmnopqrstuvwxyz") // zweites Ereignis zum Abgleich
        var iterator = client.events.makeAsyncIterator()
        #expect(await iterator.next() == .unauthorized) // nur vom zweiten Aufruf
    }

    @Test func forbiddenUnderApiV1EmitsEvent() async {
        let (client, api, store) = makeClient(cookie: "session=abc") { _ in StubReply(403, json: #"{"code":"EINWILLIGUNG_FEHLT"}"#) }
        #expect(await api.me().error == .forbidden)
        #expect(store.read() == "session=abc")
        var iterator = client.events.makeAsyncIterator()
        #expect(await iterator.next() == .forbidden)
    }

    @Test func forbiddenOnAuthRouteEmitsNothing() async {
        let (client, api, _) = makeClient { _ in StubReply(403) }
        #expect(await api.signOut().error == .forbidden)
        _ = await api.me() // erzeugt das einzige Ereignis
        var iterator = client.events.makeAsyncIterator()
        #expect(await iterator.next() == .forbidden)
        #expect(StubURLProtocol.recorded.count == 2)
    }

    @Test func signInStoresCookieFromResponse() async {
        let (_, api, store) = makeClient { _ in
            StubReply(200, headers: ["Set-Cookie": "better-auth.session_token=tok; Path=/; Max-Age=7776000; HttpOnly"], json: #"{"user":{"id":"u1","name":"Erika Muster"}}"#)
        }
        let result = await api.signIn(username: "erika.muster", password: "x")
        #expect(result.value?.user?.name == "Erika Muster")
        #expect(store.read() == "better-auth.session_token=tok")
    }

    @Test func signOutClearsLocallyEvenWhenOffline() async {
        let (_, api, store) = makeClient(cookie: "session=abc") { _ in .failing(.notConnectedToInternet) }
        #expect(await api.signOut().error == .network)
        #expect(store.read() == nil)
    }

    @Test func signOutDeletesCookieWithMaxAgeZero() async {
        let (_, api, store) = makeClient(cookie: "session=abc") { _ in
            StubReply(200, headers: ["Set-Cookie": "session=; Path=/; Max-Age=0"], json: #"{"success":true}"#)
        }
        #expect(await api.signOut().value != nil)
        #expect(store.read() == nil)
    }

    @Test func doesNotFollowRedirects() async {
        let (_, api, _) = makeClient(cookie: "session=abc") { request in
            var reply = StubReply(302, headers: ["Location": "https://fremd.example.net/"])
            if request.url?.host == "api.example.org" { reply.redirectTo = URL(string: "https://fremd.example.net/") }
            return reply
        }
        #expect(await api.me().error == .unknown)
        #expect(StubURLProtocol.recorded.count == 1)
        #expect(StubURLProtocol.recorded.allSatisfy { $0.request.url?.host == "api.example.org" })
    }

    @Test func networkErrorBecomesNetwork() async {
        let (_, api, _) = makeClient { _ in .failing(.timedOut) }
        #expect(await api.me().error == .network)
    }

    @Test func unreadableBodyBecomesUnknown() async {
        let (_, api, _) = makeClient { _ in StubReply(200, json: "<html>") }
        #expect(await api.me().error == .unknown)
    }

    @Test(arguments: [nil, "", "   ", "api.example.org", "ftp://api.example.org", "http://api.example.org", "https://", "$(API_BASE_URL)"])
    func invalidBaseURLIsNetworkError(raw: String?) async {
        #expect(ApiClient.parseBaseURL(raw) == nil)
        let (_, api, _) = makeClient(base: .some(ApiClient.parseBaseURL(raw))) { _ in StubReply(200) }
        #expect(await api.me().error == .network)
        #expect(StubURLProtocol.recorded.isEmpty)
    }

    @Test func validBaseURLs() {
        #expect(ApiClient.parseBaseURL(" https://api.example.org ")?.host == "api.example.org")
        #expect(ApiClient.parseBaseURL("http://localhost:8080")?.port == 8080)
        #expect(ApiClient.parseBaseURL("https://user:pw@api.example.org") == nil)
    }

    @Test func imageOnlyLoadsContractPaths() async {
        let (_, api, _) = makeClient(cookie: "session=abc") { _ in StubReply(200, json: "jpegbytes") }
        let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

        #expect(await api.personImage(path: "/api/v1/personen/\(id)/bild?v=3").value == Data("jpegbytes".utf8))
        #expect(await api.personImage(path: "https://fremd.example.net/api/v1/personen/\(id)/bild").error == .notFound)
        #expect(await api.personImage(path: "/api/v1/raenge/\(id)/abzeichen").error == .notFound)
        #expect(await api.badgeImage(path: "/api/v1/raenge/\(id)/abzeichen").value != nil)
        #expect(StubURLProtocol.recorded.count == 2)
    }

    @Test func unitLogoLoadsOnlyTheUnitLogoPath() async {
        let (_, api, _) = makeClient(cookie: "session=abc") { _ in StubReply(200, json: "png") }
        let id = "0f8fad5b-d9cb-469f-a165-70867728950e"

        #expect(await api.unitLogo(unitId: id).value == Data("png".utf8))
        #expect(StubURLProtocol.recorded.last?.request.url?.path == "/api/v1/einheiten/\(id)/logo")
        // Eine Kennung, die keine UUID ist, geht nie hinaus.
        let before = StubURLProtocol.recorded.count
        #expect(await api.unitLogo(unitId: "../ich").error == .notFound)
        #expect(StubURLProtocol.recorded.count == before)
    }

    @Test func tooLargeImageIsRejected() async {
        let (_, api, _) = makeClient { _ in
            var reply = StubReply(200)
            reply.body = Data(count: FireResponseAPI.maxImageBytes + 1)
            return reply
        }
        let id = "0f8fad5b-d9cb-469f-a165-70867728950e"
        #expect(await api.personImage(path: "/api/v1/personen/\(id)/bild").error == .unknown)
    }

    @Test func pathValuesAreEncoded() {
        #expect(Endpoint.program.path("a/b c") == "/api/v1/programme/a%2Fb%20c")
    }
}
