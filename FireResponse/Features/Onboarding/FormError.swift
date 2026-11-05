import Foundation

/// Was bei Anmelden, Passwort und Einwilligung schiefgehen kann, als freundlicher Satz mit nächstem Schritt.
/// Der Text des Servers wird nie angezeigt; nur Status und `code` zählen (SR: keine Server-Texte in der Oberfläche).
enum FormError: Equatable, Error {
    case invalidCredentials(repeated: Bool)
    case adminOnly
    case missingCredentials
    case currentPasswordWrong
    case passwordUnchanged
    case passwordCompromised
    case passwordTooShort
    case passwordTooLong
    case appOutdated
    case tooManyRequests(waitSeconds: Int?)
    case offline
    case unknown

    /// Fehler eines Aufrufs (401 beim Anmelden ist `invalidCredentials`, das setzt der Aufrufer).
    static func from(_ error: ApiError, retryAfterSeconds: Int? = nil) -> FormError {
        switch error {
        case .appOutdated: .appOutdated
        case .tooManyRequests: .tooManyRequests(waitSeconds: retryAfterSeconds)
        case .network: .offline
        default: .unknown
        }
    }

    /// Fehlercodes von `change-password`.
    static func password(code: String?, error: ApiError, retryAfterSeconds: Int?) -> FormError {
        switch code {
        case "INVALID_PASSWORD": .currentPasswordWrong
        case "PASSWORT_UNVERAENDERT": .passwordUnchanged
        case "PASSWORD_COMPROMISED": .passwordCompromised
        case "PASSWORD_TOO_SHORT": .passwordTooShort
        case "PASSWORD_TOO_LONG": .passwordTooLong
        default: from(error, retryAfterSeconds: retryAfterSeconds)
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .invalidCredentials, .adminOnly, .missingCredentials: "Anmelden hat nicht geklappt"
        case .currentPasswordWrong, .passwordUnchanged, .passwordCompromised, .passwordTooShort, .passwordTooLong:
            "Passwort speichern hat nicht geklappt"
        case .appOutdated: "Diese App ist zu alt"
        case .tooManyRequests: "Zu viele Versuche"
        case .offline: "Keine Verbindung"
        case .unknown: "Etwas ist schiefgelaufen"
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .invalidCredentials(let repeated):
            repeated
                // swiftlint:disable:next line_length
                ? "Nach mehreren Fehlversuchen sperrt der Server dein Konto für einige Minuten, auch für das richtige Passwort. Warte kurz und versuche es dann in Ruhe nochmals. Sonst hilft deine Leitung."
                : "Prüfe Benutzername und Passwort. Hast du dein Passwort schon geändert, gilt das Startpasswort nicht mehr. Sonst hilft deine Leitung."
        case .missingCredentials: "Bitte gib deinen Benutzernamen und dein Passwort ein."
        case .adminOnly: "Admins melden sich im Admin-Bereich an. In der App geht das nicht."
        case .currentPasswordWrong: "Das Startpasswort stimmt nicht. Gib es nochmals ein."
        case .passwordUnchanged: "Das neue Passwort muss anders sein als das Startpasswort."
        case .passwordCompromised: "Dieses Passwort ist aus einem Datenleck bekannt. Wähle ein anderes."
        case .passwordTooShort: "Das Passwort braucht mindestens 12 Zeichen."
        case .passwordTooLong: "Das Passwort darf höchstens 128 Zeichen lang sein."
        case .appOutdated: "Bitte installiere die neue Version aus dem App Store."
        case .tooManyRequests(let seconds):
            if let seconds { "Bitte warte \(Self.waitText(seconds)) und versuche es dann nochmals." } else { "Bitte warte einen Moment und versuche es dann nochmals." }
        case .offline: "Prüfe dein Internet und versuche es nochmals."
        case .unknown: "Das liegt nicht an dir. Versuche es in ein paar Minuten nochmals."
        }
    }

    /// Wartezeit: bis 90 Sekunden in Sekunden, darüber in Minuten (aufgerundet).
    static func waitText(_ seconds: Int) -> String {
        if seconds <= 90 {
            let count = max(seconds, 1)
            return count == 1 ? String(localized: "1 Sekunde") : String(localized: "\(count) Sekunden")
        }
        return String(localized: "\((seconds + 59) / 60) Minuten")
    }
}
