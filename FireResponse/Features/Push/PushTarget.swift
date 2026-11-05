import Foundation
import Observation

/// Wohin ein Push führt: in eine Übung (Android: `PushTarget.Appointment`, Server: `typ` `programm`).
nonisolated enum PushTarget: Equatable, Sendable {
    case appointment(id: String)

    /// Eine Kennung hat 36 Zeichen aus Hex und `-`. Der Inhalt eines Pushes kommt von aussen: Was keine Kennung ist,
    /// führt nirgends hin (es würde sonst im Pfad einer Anfrage landen).
    static func from(type: String?, id: String?) -> PushTarget? {
        guard let id, id.count == 36, id.allSatisfy({ $0.isASCII && ($0.isHexDigit || $0 == "-") }) else { return nil }
        return type == "programm" ? .appointment(id: id) : nil
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

    func open(_ target: PushTarget) { pending = target }

    func consume() -> PushTarget? {
        defer { pending = nil }
        return pending
    }
}
