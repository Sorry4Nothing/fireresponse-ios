import Foundation
import Observation

/// Wohin ein Push führt: in eine Übung (Android: `PushTarget.Appointment`, Server: `typ` `programm`).
nonisolated enum PushTarget: Equatable, Sendable {
    case appointment(id: String)
    /// Der Verlauf des Infokanals einer Einheit (Server: `typ` `infokanal`, `id` ist die Einheit).
    case infoChannel(unitId: String)

    /// Eine Kennung hat 36 Zeichen aus Hex und `-`. Der Inhalt eines Pushes kommt von aussen: Was keine Kennung ist,
    /// führt nirgends hin (es würde sonst im Pfad einer Anfrage landen).
    static func from(type: String?, id: String?) -> PushTarget? {
        guard let id, id.count == 36, id.allSatisfy({ $0.isASCII && ($0.isHexDigit || $0 == "-") }) else { return nil }
        switch type {
        case "programm": return .appointment(id: id)
        case "infokanal": return .infoChannel(unitId: id)
        default: return nil // auch `mitteilung` (Push aus dem Backend, ohne `id`): öffnet nur die App
        }
    }

    /// Aus den Daten des Pushes (`userInfo` der Mitteilung), Schlüssel `typ` und `id`.
    static func from(userInfo: [AnyHashable: Any]) -> PushTarget? {
        from(type: userInfo["typ"] as? String, id: userInfo["id"] as? String)
    }
}

/// Reicht das Ziel eines angetippten Pushes weiter. Die Übungsliste liest `pending`, öffnet die Übung und ruft `consume()`.
/// Ein Tipp beim Kaltstart landet auch hier: `pending` bleibt stehen, bis jemand es abholt.
@MainActor @Observable
final class PushRouter {
    private(set) var pending: PushTarget?
    /// Der Verlauf, den der Infokanal-Reiter öffnen soll (Einheit); getrennt von `pending`, damit die Übungsliste ihn nicht abholt.
    private(set) var pendingInfoChannel: String?

    func open(_ target: PushTarget) {
        switch target {
        case .appointment: pending = target
        case .infoChannel(let unitId): pendingInfoChannel = unitId
        }
    }

    func consumeInfoChannel() -> String? {
        defer { pendingInfoChannel = nil }
        return pendingInfoChannel
    }

    func consume() -> PushTarget? {
        defer { pending = nil }
        return pending
    }
}
