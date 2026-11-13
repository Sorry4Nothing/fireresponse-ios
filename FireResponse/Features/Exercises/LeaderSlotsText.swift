import Foundation

/// Texte zu den Plätzen der Leitenden (Issue #66). «Voll» und «Warteliste» sind kein Fehler und haben keine Alarmfarbe.
nonisolated enum LeaderSlotsText {
    enum Kind: Equatable { case free, full, waiting }

    struct Line: Equatable {
        let kind: Kind
        /// Für die Karte und den Kopf der Platzanzeige.
        let text: String
        /// Für VoiceOver.
        let spoken: String
        let symbol: String
    }

    /// `own` ist die eigene Anmeldung (`warteliste` zeigt den Platz auf der Liste).
    static func line(_ slots: LeaderSlots, own: String?) -> Line {
        if own == "warteliste" {
            let position = slots.ownPosition
            let text = position.map { String(localized: "Warteliste, Platz \($0)") } ?? String(localized: "Warteliste")
            let spoken = position.map { String(localized: "Du stehst auf der Warteliste, Platz \($0)") } ?? String(localized: "Du stehst auf der Warteliste")
            return Line(kind: .waiting, text: text, spoken: spoken, symbol: "clock")
        }
        if slots.isFull || slots.free <= 0 {
            return Line(kind: .full, text: String(localized: "Voll"), spoken: String(localized: "Voll, Warteliste möglich"), symbol: "lock")
        }
        let text = slots.free == 1 ? String(localized: "Noch 1 Platz frei") : String(localized: "Noch \(slots.free) Plätze frei")
        return Line(kind: .free, text: text, spoken: text, symbol: "person.2")
    }

    /// Wartende im Kopf der Platzanzeige: «2 Personen warten».
    static func waitingText(_ count: Int) -> String? {
        switch count {
        case ..<1: nil
        case 1: String(localized: "1 Person wartet")
        default: String(localized: "\(count) Personen warten")
        }
    }
}
