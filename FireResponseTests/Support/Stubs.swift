import Foundation
import os
@testable import FireResponse

/// Speicher im Arbeitsspeicher statt Keychain.
nonisolated final class InMemorySessionStore: SessionStore {
    private let cookie = OSAllocatedUnfairLock<String?>(initialState: nil)

    init(cookie: String? = nil) { self.cookie.withLock { $0 = cookie } }
    func read() -> String? { cookie.withLock { $0 } }
    func write(_ value: String) { cookie.withLock { $0 = value } }
    func clear() { cookie.withLock { $0 = nil } }
}

nonisolated struct StubReply: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()
    var error: URLError?
    var redirectTo: URL?

    init(_ status: Int = 200, headers: [String: String] = [:], json: String = "") {
        self.status = status
        self.headers = headers
        body = Data(json.utf8)
    }

    static func failing(_ code: URLError.Code) -> StubReply {
        var reply = StubReply()
        reply.error = URLError(code)
        return reply
    }
}

nonisolated struct RecordedRequest: Sendable {
    let request: URLRequest
    let body: Data

    func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
}

/// Fängt jede Anfrage der Test-URLSession ab. Die Tests laufen nacheinander (`.serialized`), der Zustand ist darum global.
nonisolated final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct State {
        var handler: (@Sendable (URLRequest) -> StubReply)?
        var recorded: [RecordedRequest] = []
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func install(_ handler: @escaping @Sendable (URLRequest) -> StubReply) {
        state.withLock { $0 = State(handler: handler) }
    }

    static var recorded: [RecordedRequest] { state.withLock { $0.recorded } }

    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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
        let sentBody = body
        let reply = Self.state.withLock { state -> StubReply in
            state.recorded.append(RecordedRequest(request: request, body: sentBody))
            return state.handler?(request) ?? StubReply(500)
        }
        guard let url = request.url else { return }
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
        guard let response else { return }
        if let target = reply.redirectTo {
            // Verweigert der Delegate die Weiterleitung, gilt die 3xx-Antwort selbst als Ergebnis.
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
