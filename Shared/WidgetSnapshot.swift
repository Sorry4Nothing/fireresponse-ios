import Foundation

/// Was das Widget zeigt: die nächsten Übungen, fertig aufbereitet. Die App schreibt es beim Laden der Liste, das Widget liest nur.
/// Es steht im App-Group-Container und enthält Vornamen der eigenen Kinder; beim Abmelden wird es gelöscht.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    enum Stand: String, Codable, Sendable { case yes, no, open }

    struct Person: Codable, Equatable, Sendable {
        let name: String
        let stand: Stand
    }

    struct Row: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let title: String
        /// Kürzel der Einheit, «JF» oder «KF».
        let unitType: String
        /// «MI 18.11. · 19:00»
        let when: String
        /// «2 von 2», vor dem Anmeldefenster «ab 5.12.», ohne Anmeldung `nil`.
        let count: String?
        /// Leer vor dem Anmeldefenster und wenn die Übung keine Antwort verlangt.
        let people: [Person]
        /// Der ganze Satz für VoiceOver.
        let spoken: String
        /// Danach zählt die Übung nicht mehr; das Widget blendet sie dann aus.
        let endsAt: Date
    }

    /// So viele Zeilen zeigt das Widget (mittlere Grösse).
    static let visibleRows = 2

    /// So viele Übungen legt die App ab, damit das Widget nachrücken kann, wenn eine endet.
    static let storedRows = 4

    let rows: [Row]
}

/// Die Datei im App-Group-Container. Ohne Eintrag (nie geschrieben, abgemeldet) zeigt das Widget «Bitte melde dich in der App an».
nonisolated struct WidgetSnapshotStore: Sendable {
    static let groupIdentifier = "group.ch.fireresponse.app"

    let url: URL

    /// `nil`, wenn der Container fehlt (App Group nicht freigegeben).
    static var appGroup: WidgetSnapshotStore? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
            .map { WidgetSnapshotStore(url: $0.appending(path: "widget.json")) }
    }

    func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(WidgetSnapshot.self, from: data)
    }

    func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? Self.encoder.encode(snapshot) else { return }
        // Erst nach dem ersten Entsperren lesbar: Das Widget muss auch bei gesperrtem Gerät laden können.
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Der Tipp aufs Widget: `fireresponse://programm/<Kennung>`. Die App prüft die Kennung wie bei einem Push (`PushTarget.from`).
nonisolated enum WidgetLink {
    static let scheme = "fireresponse"
    private static let host = "programm"

    static func url(programId: String) -> URL? {
        URL(string: "\(scheme)://\(host)/\(programId)")
    }

    static func programId(from url: URL) -> String? {
        url.scheme == scheme && url.host == host ? url.lastPathComponent : nil
    }
}
