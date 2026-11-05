import Foundation

/// Regeln für ein neues Passwort, damit der Screen schon vor dem Senden zeigt, was fehlt. Der Server prüft sie nochmals
/// (und zusätzlich auf bekannte Datenlecks).
struct PasswordRules: Equatable {
    static let minLength = 12

    let new: String
    let repeated: String
    let current: String
    let username: String?

    var longEnough: Bool { new.count >= Self.minLength }
    var notUsername: Bool { !new.isEmpty && new.caseInsensitiveCompare(username ?? "") != .orderedSame }
    var notStartPassword: Bool { !new.isEmpty && new != current }
    var matches: Bool { !new.isEmpty && new == repeated }
    var allMet: Bool { longEnough && notUsername && notStartPassword }
    /// Zum Speichern müssen die Regeln erfüllt und beide Felder gleich sein.
    var canSave: Bool { allMet && matches }
}
