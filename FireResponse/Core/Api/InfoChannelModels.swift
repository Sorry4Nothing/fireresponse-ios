import Foundation

/// Ein Infokanal je Einheit (Issue #68): Einwegkanal, Kommando und Leitung schreiben, alle anderen der Einheit lesen.
/// Vertrag: Vault «FR API Vertrag Apps Nr 27-34»; `openapi.yaml` führt ihn noch nicht.
nonisolated struct InfoChannel: Decodable, Sendable, Equatable, Identifiable {
    let unit: ProgramUnit
    /// «Infokanal Jugendfeuerwehr Meilen»
    let name: String
    let canWrite: Bool
    let unread: Int
    let lastMessageAt: Date?
    var id: String { unit.id }

    enum CodingKeys: String, CodingKey {
        case unit = "einheit"
        case name
        case canWrite = "darfSchreiben"
        case unread = "ungelesen"
        case lastMessageAt = "letzteMitteilungAm"
    }

    func withUnread(_ count: Int) -> InfoChannel {
        InfoChannel(unit: unit, name: name, canWrite: canWrite, unread: count, lastMessageAt: lastMessageAt)
    }
}

/// `GET /api/v1/infokanaele`: eine Zeile je Einheit; die Person hat 0, 1 oder mehrere.
nonisolated struct InfoChannelList: Decodable, Sendable, Equatable {
    let channels: [InfoChannel]

    enum CodingKeys: String, CodingKey { case channels = "infokanaele" }
}

/// Absender einer Mitteilung. `role`: `kommando` (auch die Stellvertretung) oder `leitung`; `nil`, wenn die Person die Rolle nicht mehr hat.
nonisolated struct InfoAuthor: Decodable, Sendable, Equatable {
    let name: String
    let role: String?
    let imagePath: String?

    enum CodingKeys: String, CodingKey {
        case name
        case role = "rolle"
        case imagePath = "bildUrl"
    }
}

/// Eine Mitteilung. Eine gelöschte hat `isDeleted`, keinen Text und keinen Absender und bleibt als Platzhalter stehen.
nonisolated struct InfoMessage: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let text: String?
    let isDeleted: Bool
    let isEdited: Bool
    let createdAt: Date
    let author: InfoAuthor?
    let isOwn: Bool
    let canEdit: Bool
    let canDelete: Bool

    enum CodingKeys: String, CodingKey {
        case id, text, author
        case isDeleted = "geloescht"
        case isEdited = "bearbeitet"
        case createdAt = "erstelltAm"
        case isOwn = "eigene"
        case canEdit = "darfBearbeiten"
        case canDelete = "darfLoeschen"
    }

    /// Die Anzeige löscht lokal, bis der nächste Abruf den Stand des Servers bringt.
    var asDeleted: InfoMessage {
        InfoMessage(id: id, text: nil, isDeleted: true, isEdited: isEdited, createdAt: createdAt, author: nil, isOwn: isOwn, canEdit: false, canDelete: false)
    }
}

/// Eine Seite des Verlaufs, neueste zuerst. `next` ist das `vor` der nächsten Seite, `nil` am Ende.
nonisolated struct InfoMessagePage: Decodable, Sendable, Equatable {
    let canWrite: Bool
    let messages: [InfoMessage]
    let next: String?

    enum CodingKeys: String, CodingKey {
        case canWrite = "darfSchreiben"
        case messages = "mitteilungen"
        case next = "naechste"
    }
}

nonisolated struct InfoTextBody: Encodable, Sendable {
    let text: String
}
