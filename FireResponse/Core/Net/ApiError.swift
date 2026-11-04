import Foundation

/// Einheitliche Fehler der API. Der Text des Servers wird nie angezeigt und nie weitergereicht: nur Status und `code`.
nonisolated enum ApiError: Error, Sendable, Equatable {
    case notSignedIn
    case forbidden
    case notFound
    case appOutdated
    case tooManyRequests
    /// 409 `PROGRAMM_GESCHLOSSEN` (und jedes andere 409): Programm abgesagt oder begonnen.
    case registrationClosed
    /// 409 `ANMELDEFENSTER_NICHT_OFFEN`: Die Anmeldung öffnet erst später.
    case registrationNotOpen
    /// 409 `KEINE_ANMELDUNG`: Die Einheit hat die Art des Termins nicht für die Anmeldung freigegeben.
    case noRegistration
    /// 409 `PROGRAMM_BEGONNEN`: Die Leitung kann sich nach dem Beginn nicht mehr ändern.
    case appointmentStarted
    case network
    case unknown

    /// `code` ist der Fehlercode des Servers; er unterscheidet bei 409 die Fälle.
    static func from(status: Int, code: String? = nil) -> ApiError {
        switch status {
        case 401: .notSignedIn
        case 403: .forbidden
        case 404: .notFound
        case 409:
            switch code {
            case "PROGRAMM_BEGONNEN": .appointmentStarted
            case "ANMELDEFENSTER_NICHT_OFFEN": .registrationNotOpen
            case "KEINE_ANMELDUNG": .noRegistration
            default: .registrationClosed
            }
        case 426: .appOutdated
        case 429: .tooManyRequests
        default: .unknown
        }
    }
}

/// Ergebnis jedes Aufrufs; der Client wirft nie.
/// `code`: Fehlercode des Servers (z. B. `PASSWORD_COMPROMISED`). `retryAfterSeconds`: Wartezeit bei 429.
nonisolated enum ApiResult<Value: Sendable>: Sendable {
    case ok(Value)
    case failure(ApiError, code: String? = nil, retryAfterSeconds: Int? = nil)

    var value: Value? {
        if case .ok(let value) = self { value } else { nil }
    }

    var error: ApiError? {
        if case .failure(let error, _, _) = self { error } else { nil }
    }

    func map<T: Sendable>(_ transform: (Value) -> T) -> ApiResult<T> {
        switch self {
        case .ok(let value): .ok(transform(value))
        case .failure(let error, let code, let retry): .failure(error, code: code, retryAfterSeconds: retry)
        }
    }
}

extension ApiResult: Equatable where Value: Equatable {}

/// Ereignisse, auf die die App ausserhalb des einzelnen Aufrufs reagiert (siehe `ApiClient.events`).
nonisolated enum ApiEvent: Sendable, Equatable {
    /// 401 ausser bei der Anmeldung: Die Sitzung ist beendet, das Cookie ist schon gelöscht. Zurück zum Login.
    case unauthorized
    /// 403 unter `/api/v1`: «kein Recht», aber auch «Passwortwechsel offen» oder «Einwilligung fehlt». Die App liest
    /// dann `FireResponseAPI.me()` (bleibt offen) und führt zum Passwortwechsel oder zur Einwilligung.
    case forbidden
}
