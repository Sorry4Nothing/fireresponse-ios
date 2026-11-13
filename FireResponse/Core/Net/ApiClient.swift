import Foundation

nonisolated enum ApiBody: Sendable {
    case none
    case encoded(Data)
    /// Rohe Bytes, z. B. ein Bild (der Server erkennt den Typ an den ersten Bytes).
    case bytes(Data, contentType: String)

    static func json(_ value: some Encodable) -> ApiBody {
        .encoded((try? JSONEncoder().encode(value)) ?? Data())
    }
}

/// Verweigert jede Weiterleitung: Der Cookie-Header ginge sonst womöglich an einen fremden Host. Die 3xx-Antwort gilt als Fehler.
private nonisolated final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Dünner Zugang zur FireResponse-API. Wirft nie: jede Antwort kommt als `ApiResult`.
/// Setzt `Origin`, `X-App-Version` und das Cookie aus dem `SessionStore` und führt die Cookies der Antworten nach.
actor ApiClient {
    private static let originHeader = "fireresponse://"
    /// Eine Stunde ist die Obergrenze für `X-Retry-After`: Was der Server schickt, ist nicht vertrauenswürdig.
    private static let maxRetryAfter = 3600
    static let defaultMaxBytes = 2 * 1024 * 1024

    private let baseURL: URL?
    private let appVersion: String
    private let store: SessionStore
    private let session: URLSession
    private let continuation: AsyncStream<ApiEvent>.Continuation

    /// Ereignisse für die App (ein Empfänger): beendete Sitzung (401) und 403 unter `/api/v1`.
    nonisolated let events: AsyncStream<ApiEvent>

    /// `baseURL` `nil` (leer oder ungültig) heisst: jeder Aufruf endet mit `.network`.
    init(
        baseURL: URL?,
        appVersion: String,
        store: SessionStore,
        configuration: URLSessionConfiguration = .ephemeral
    ) {
        self.baseURL = baseURL
        self.appVersion = appVersion
        self.store = store
        let configuration = configuration
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
        (events, continuation) = AsyncStream.makeStream(of: ApiEvent.self, bufferingPolicy: .bufferingNewest(8))
    }

    /// Mit `APIBaseURL` und Version aus der Info.plist des Bundles.
    static func live(store: SessionStore, bundle: Bundle = .main) -> ApiClient {
        ApiClient(
            baseURL: parseBaseURL(bundle.object(forInfoDictionaryKey: "APIBaseURL") as? String),
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            store: store
        )
    }

    /// Nur `https` (`http` nur für den eigenen Rechner), ohne Zugangsdaten, Query und Fragment; sonst `nil`.
    nonisolated static func parseBaseURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let parts = URLComponents(string: raw), let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil
        else { return nil }
        switch parts.scheme?.lowercased() {
        case "https": return parts.url
        case "http" where ["localhost", "127.0.0.1", "::1"].contains(host): return parts.url
        default: return nil
        }
    }

    /// Ob ein Cookie gespeichert ist.
    func hasSession() -> Bool { store.read() != nil }

    /// Vergisst das Cookie (auch ein halbes).
    func forgetSession() { store.clear() }

    /// Aufruf mit JSON-Antwort. Eine Antwort, die sich nicht lesen lässt, ist `.unknown`.
    func send<T: Decodable & Sendable>(
        _ endpoint: Endpoint,
        values: [String] = [],
        query: [URLQueryItem] = [],
        body: ApiBody = .none,
        as type: T.Type = T.self
    ) async -> ApiResult<T> {
        switch await perform(endpoint, values: values, query: query, body: body) {
        case .ok(let data):
            do {
                return .ok(try JSONDecoder.api.decode(T.self, from: data))
            } catch {
                return .failure(.unknown)
            }
        case .failure(let error, let code, let retry):
            return .failure(error, code: code, retryAfterSeconds: retry)
        }
    }

    /// Aufruf ohne Interesse an der Antwort (204 oder ein Body, der nicht zählt).
    func sendDiscardingBody(
        _ endpoint: Endpoint,
        values: [String] = [],
        query: [URLQueryItem] = [],
        body: ApiBody = .none
    ) async -> ApiResult<Void> {
        await perform(endpoint, values: values, query: query, body: body).map { _ in () }
    }

    /// Roher Aufruf. `rawPath` (nur mit `Endpoint.accepts`) nimmt eine `bildUrl` des Servers entgegen.
    func perform(
        _ endpoint: Endpoint,
        values: [String] = [],
        query: [URLQueryItem] = [],
        rawPath: String? = nil,
        body: ApiBody = .none,
        maxBytes: Int = ApiClient.defaultMaxBytes
    ) async -> ApiResult<Data> {
        if let rawPath, !endpoint.accepts(path: rawPath) { return .failure(.notFound) }
        let cookie = store.read()
        guard let request = makeRequest(endpoint, path: rawPath ?? endpoint.path(with: values), query: query, body: body, cookie: cookie) else {
            return .failure(.network)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, let url = request.url else { return .failure(.network) }
            let setCookie = http.value(forHTTPHeaderField: "Set-Cookie")
            if setCookie != nil {
                if let merged = CookieJar.merge(current: store.read(), setCookie: setCookie, url: url) {
                    store.write(merged)
                } else {
                    store.clear()
                }
            }
            return evaluate(http, data: data, endpoint: endpoint, cookieSent: cookie, maxBytes: maxBytes)
        } catch {
            return .failure(.network)
        }
    }

    private func makeRequest(_ endpoint: Endpoint, path: String, query: [URLQueryItem], body: ApiBody, cookie: String?) -> URLRequest? {
        guard let baseURL, var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        let basePath = parts.percentEncodedPath.hasSuffix("/") ? String(parts.percentEncodedPath.dropLast()) : parts.percentEncodedPath
        let pieces = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        parts.percentEncodedPath = basePath + pieces[0]
        if pieces.count > 1 { parts.percentEncodedQuery = String(pieces[1]) }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(appVersion, forHTTPHeaderField: "X-App-Version")
        request.setValue(Self.originHeader, forHTTPHeaderField: "Origin")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        switch body {
        case .none: break
        case .encoded(let data):
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        case .bytes(let data, let contentType):
            request.httpBody = data
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func evaluate(
        _ http: HTTPURLResponse,
        data: Data,
        endpoint: Endpoint,
        cookieSent: String?,
        maxBytes: Int
    ) -> ApiResult<Data> {
        let status = http.statusCode
        guard (200..<300).contains(status) else {
            // Nicht löschen, wenn inzwischen ein neues Cookie da ist (parallele Anmeldung).
            if status == 401, endpoint != .signIn {
                if store.read() == cookieSent { store.clear() }
                continuation.yield(.unauthorized)
            }
            if status == 403, endpoint.isAppRoute { continuation.yield(.forbidden) }
            let body = (400..<600).contains(status) ? Self.errorBody(in: data) : nil
            let code = body?.code
            if status == 503, code == "WARTUNG" {
                // Wartung hat Vorrang: Text und Ende kommen aus dem Body, sonst zeigt die App ihren Standardtext.
                continuation.yield(.maintenance(MaintenanceInfo(text: body?.message, until: body?.ende.flatMap(Date.fromAPI))))
            }
            let retry = status == 429
                ? http.value(forHTTPHeaderField: "X-Retry-After").flatMap { Int($0) }.map { min(max($0, 1), Self.maxRetryAfter) }
                : nil
            return .failure(.from(status: status, code: code), code: code, retryAfterSeconds: retry)
        }
        // shortcut: Antwort wird ganz geladen und danach geprüft, bei grösseren Bildern auf `bytes(for:)` mit Abbruch wechseln.
        return data.count > maxBytes ? .failure(.unknown) : .ok(data)
    }

    private struct ErrorBody: Decodable {
        let code: String?
        let message: String?
        let ende: String?
    }

    /// `code` zählt immer. `message` und `ende` liest die App nur bei 503 `WARTUNG` (Text des Betreibers); sonst nie.
    private static func errorBody(in data: Data) -> ErrorBody? {
        try? JSONDecoder().decode(ErrorBody.self, from: data)
    }
}
