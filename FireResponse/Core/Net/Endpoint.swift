import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Jeder Aufruf der App an die API steht hier und nur hier. `ApiContractTest` gleicht die Liste mit `api-vertrag/openapi.yaml` ab
/// und prüft per Quelltext-Scan, dass kein anderer Pfad im Code vorkommt. Neuer Aufruf: Fall hier ergänzen, nicht einen Pfad streuen.
nonisolated enum Endpoint: CaseIterable, Sendable {
    case signIn, signOut, session, changePassword
    case me, updateMe, putMyImage, deleteMyImage
    case consent, giveConsent, privacy
    case programs, program, participations, setParticipation, setLeadership
    case unitContact, badgeImage, personImage, unitLogo, maintenance
    case pushToken
    case infoChannels, infoMessages, postInfoMessage, editInfoMessage, deleteInfoMessage, markInfoRead

    var method: HTTPMethod {
        switch self {
        case .signIn, .signOut, .changePassword: .post
        case .updateMe: .patch
        case .infoChannels, .infoMessages: .get
        case .postInfoMessage: .post
        case .editInfoMessage, .markInfoRead: .put
        case .deleteInfoMessage: .delete
        case .putMyImage, .giveConsent, .setParticipation, .setLeadership, .pushToken: .put
        case .deleteMyImage: .delete
        case .session, .me, .consent, .privacy, .programs, .program, .participations, .unitContact, .badgeImage, .personImage, .unitLogo, .maintenance: .get
        }
    }

    /// Pfad wie im Vertrag; `{name}` sind Platzhalter, die `path(_:)` der Reihe nach füllt.
    var template: String {
        switch self {
        case .signIn: "/api/auth/sign-in/username"
        case .signOut: "/api/auth/sign-out"
        case .session: "/api/auth/get-session"
        case .changePassword: "/api/auth/change-password"
        case .me, .updateMe: "/api/v1/ich"
        case .putMyImage, .deleteMyImage: "/api/v1/ich/bild"
        case .consent, .giveConsent: "/api/v1/einwilligung"
        case .privacy: "/api/v1/datenschutz"
        case .programs: "/api/v1/programme"
        case .program: "/api/v1/programme/{id}"
        case .participations: "/api/v1/programme/{id}/teilnahmen"
        case .setParticipation: "/api/v1/programme/{id}/teilnahmen/{teilnehmendeId}"
        case .setLeadership: "/api/v1/programme/{id}/leitung"
        case .unitContact: "/api/v1/einheiten/{einheitId}/kontakt"
        case .badgeImage: "/api/v1/raenge/{id}/abzeichen"
        case .unitLogo: "/api/v1/einheiten/{einheitId}/logo"
        case .maintenance: "/api/v1/wartung"
        case .personImage: "/api/v1/personen/{id}/bild"
        case .pushToken: "/api/v1/push-token"
        case .infoChannels: "/api/v1/infokanaele"
        case .infoMessages, .postInfoMessage: "/api/v1/infokanaele/{einheitId}/mitteilungen"
        case .editInfoMessage, .deleteInfoMessage: "/api/v1/infokanaele/{einheitId}/mitteilungen/{id}"
        case .markInfoRead: "/api/v1/infokanaele/{einheitId}/gelesen"
        }
    }

    /// Routen der App (`/api/v1`); die Anmeldung unter `/api/auth` zählt nicht.
    var isAppRoute: Bool { template.hasPrefix("/api/v1/") }

    /// Der Pfad mit eingesetzten (prozentkodierten) Werten.
    func path(_ values: String...) -> String { path(with: values) }

    func path(with values: [String]) -> String {
        var remaining = values[...]
        var result = ""
        for part in template.split(separator: "/", omittingEmptySubsequences: true) {
            if part.hasPrefix("{"), let value = remaining.popFirst() {
                result += "/" + (value.addingPercentEncoding(withAllowedCharacters: .unreservedPathValue) ?? "")
            } else {
                result += "/" + part
            }
        }
        return result
    }

    /// Ob `path` (optional mit `?v=…`) genau diesem Endpunkt entspricht, mit UUIDs als Platzhaltern. Schützt Abrufe per `bildUrl`:
    /// Nur Pfade des Vertrags gehen mit der Sitzung hinaus.
    func accepts(path: String) -> Bool {
        let parts = template.split(separator: "/").map { part in
            part.hasPrefix("{") ? "[0-9a-fA-F-]{36}" : NSRegularExpression.escapedPattern(for: String(part))
        }
        let pattern = "^/" + parts.joined(separator: "/") + "(\\?[A-Za-z0-9=&._-]{0,64})?$"
        return path.range(of: pattern, options: .regularExpression) != nil
    }
}

private extension CharacterSet {
    nonisolated static let unreservedPathValue = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}
