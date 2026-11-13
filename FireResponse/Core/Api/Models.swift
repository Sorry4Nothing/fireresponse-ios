import Foundation

// DTOs nach `api-vertrag/openapi.yaml`. Namen englisch, die JSON-Schlüssel stehen in den CodingKeys.
// Text-Aufzählungen des Vertrags (Status, Rolle, Typ) bleiben `String`, damit ein neuer Wert nie das Dekodieren bricht.

nonisolated extension JSONDecoder {
    /// `date-time` des Servers kommt mit und ohne Millisekunden (`2027-03-01T17:00:00.000Z`).
    static var api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = Date.fromAPI(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Kein Datum: \(text)"))
        }
        return decoder
    }
}

nonisolated extension Date {
    /// ISO 8601 mit Zeitzone, mit und ohne Millisekunden.
    static func fromAPI(_ text: String) -> Date? {
        (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))) ?? (try? Date(text, strategy: Date.ISO8601FormatStyle()))
    }
}

/// Was der Wartungsbildschirm zeigt: Text und voraussichtliches Ende, beides vom Betreiber und beides optional.
/// Das ist die einzige Stelle, an der die App einen Text des Servers anzeigt: Das Panel setzt ihn (höchstens 280 Zeichen), er ist kein Fehlertext.
nonisolated struct MaintenanceInfo: Sendable, Equatable {
    static let maxTextLength = 280
    let text: String?
    let until: Date?

    init(text: String?, until: Date?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.text = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxTextLength))
        self.until = until
    }
}

/// `GET /api/v1/wartung`: öffentlich, ohne Sitzung, antwortet immer 200.
nonisolated struct MaintenanceStatus: Decodable, Sendable, Equatable {
    let isActive: Bool
    let text: String?
    let until: Date?
    let since: Date?

    enum CodingKeys: String, CodingKey {
        case isActive = "aktiv"
        case text
        case until = "ende"
        case since = "seit"
    }

    /// `nil`, wenn keine Wartung läuft.
    var info: MaintenanceInfo? { isActive ? MaintenanceInfo(text: text, until: until) : nil }
}

/// Schweizer Kalendertag (`JJJJ-MM-TT`), unabhängig von der Zeitzone des Geräts.
nonisolated struct SwissDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    static let timeZone = TimeZone(identifier: "Europe/Zurich") ?? .gmt
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    let year: Int
    let month: Int
    let day: Int

    init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              DateComponents(calendar: Self.calendar, year: year, month: month, day: day).isValidDate
        else { return nil }
        (self.year, self.month, self.day) = (year, month, day)
    }

    /// Der Kalendertag von `date` in Schweizer Zeit.
    init(date: Date) {
        let parts = Self.calendar.dateComponents([.year, .month, .day], from: date)
        (year, month, day) = (parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let day = SwissDay(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Kein Datum JJJJ-MM-TT"))
        }
        self = day
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func < (lhs: SwissDay, rhs: SwissDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

// MARK: Anmeldung

nonisolated struct SignInRequest: Encodable, Sendable {
    let username: String
    let password: String
}

/// Antwort der Anmeldung. `twoFactorRedirect`: Der Server verlangt den zweiten Faktor, eine Sitzung gibt es dann noch nicht.
nonisolated struct SignInResponse: Decodable, Sendable, Equatable {
    let twoFactorRedirect: Bool?
    let user: AuthUser?

    var needsSecondFactor: Bool { twoFactorRedirect == true }
}

nonisolated struct AuthUser: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let username: String?
    let role: String?
    let twoFactorEnabled: Bool?
    let mustChangePassword: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, username, role, twoFactorEnabled
        case mustChangePassword = "mussPasswortAendern"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        twoFactorEnabled = try container.decodeIfPresent(Bool.self, forKey: .twoFactorEnabled)
        mustChangePassword = try container.decodeIfPresent(Bool.self, forKey: .mustChangePassword) ?? false
    }
}

/// `GET /api/auth/get-session`: ohne Sitzung `null` (dann 200). Das Sitzungstoken liest die App nicht.
nonisolated struct AuthSession: Decodable, Sendable, Equatable {
    let user: AuthUser
}

nonisolated struct ChangePasswordRequest: Encodable, Sendable {
    let currentPassword: String
    let newPassword: String
}

// MARK: Profil

/// Rang-Abzeichen: `abbreviation` immer, dazu `stars` (0 bis 2) oder `imagePath` (für `FireResponseAPI.badgeImage`), sonst nur das Kürzel.
nonisolated struct Badge: Decodable, Sendable, Equatable {
    let abbreviation: String
    let stars: Int?
    let imagePath: String?

    enum CodingKeys: String, CodingKey {
        case abbreviation = "kuerzel"
        case stars = "sterne"
        case imagePath = "bildUrl"
    }
}

/// Eine Einheit, in der die Person Kommandant, Stellvertretung oder Leitung ist. `type`: `jf` oder `kf`; `role`: `kommandant`,
/// `stellvertretung` oder `leitung`.
nonisolated struct ProfileUnit: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let type: String
    let district: String
    let role: String
    let badge: Badge?

    enum CodingKeys: String, CodingKey {
        case id, name
        case badge = "abzeichen"
        case type = "typ"
        case district = "bezirk"
        case role = "rolle"
    }
}

/// Eine teilnehmende Person, für die das Konto antwortet. `kind`: `eltern` oder `selbst`.
nonisolated struct ProfileParticipant: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let firstName: String
    let lastName: String
    let unitId: String
    /// Name und Typ (`jf` oder `kf`) der Einheit; fehlen bei einem Server vor dieser Fassung.
    let unitName: String?
    let unitType: String?
    let kind: String
    let badge: Badge?

    enum CodingKeys: String, CodingKey {
        case id
        case badge = "abzeichen"
        case unitName = "einheitName"
        case unitType = "einheitTyp"
        case firstName = "vorname"
        case lastName = "nachname"
        case unitId = "einheitId"
        case kind = "art"
    }
}

/// `GET /api/v1/ich`. Bleibt auch bei offenem Passwortwechsel und fehlender Einwilligung erreichbar.
/// `pushRegistrations` fehlt bei Personen ohne Rolle in einer Einheit.
nonisolated struct Profile: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let username: String
    let isCantonAdmin: Bool
    let hasSecondFactor: Bool
    let hasConsented: Bool
    let mustChangePassword: Bool
    let phone: String?
    let imagePath: String?
    let pushPrograms: Bool
    let pushRegistrations: Bool?
    let units: [ProfileUnit]
    let participants: [ProfileParticipant]

    enum CodingKeys: String, CodingKey {
        case id, name, phone = "telefon"
        case username = "benutzername"
        case isCantonAdmin = "kantonsadmin"
        case hasSecondFactor = "zweiterFaktor"
        case hasConsented = "einwilligung"
        case mustChangePassword = "mussPasswortAendern"
        case imagePath = "bildUrl"
        case pushPrograms = "pushProgramme"
        case pushRegistrations = "pushAnmeldungen"
        case units = "einheiten"
        case participants = "teilnehmende"
    }
}

/// `PATCH /api/v1/ich`: mindestens ein Feld; `nil` bleibt weg. `phone`: `.some("…")` setzt die Nummer, `.some(nil)` entfernt sie.
nonisolated struct ProfileSettings: Encodable, Sendable {
    var pushPrograms: Bool?
    var pushRegistrations: Bool?
    var phone: String??

    enum CodingKeys: String, CodingKey {
        case pushPrograms = "pushProgramme"
        case pushRegistrations = "pushAnmeldungen"
        case phone = "telefon"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(pushPrograms, forKey: .pushPrograms)
        try container.encodeIfPresent(pushRegistrations, forKey: .pushRegistrations)
        if let phone { try container.encode(phone, forKey: .phone) }
    }
}

/// `GET /api/v1/einwilligung`: `isValid`: Die Person hat der aktuellen Fassung zugestimmt. Eine neue `version` heisst: neu fragen.
nonisolated struct Consent: Decodable, Sendable, Equatable {
    let version: Int
    let text: String
    let isValid: Bool

    enum CodingKeys: String, CodingKey {
        case version, text
        case isValid = "gueltig"
    }
}

nonisolated struct PrivacySection: Decodable, Sendable, Equatable {
    let title: String
    /// Klartext; Absätze und Listenpunkte («– ») trennt eine Leerzeile.
    let text: String

    enum CodingKeys: String, CodingKey {
        case title = "titel"
        case text
    }
}

nonisolated struct Privacy: Decodable, Sendable, Equatable {
    let version: Int
    let sections: [PrivacySection]

    enum CodingKeys: String, CodingKey {
        case version
        case sections = "abschnitte"
    }
}

// MARK: Programme

/// `kommandant` oder `stellvertretung` (Kontakt eines Programms oder einer Einheit).
nonisolated struct Contact: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let role: String
    let imagePath: String?
    let badge: Badge?
    /// Nur für Eltern und Teilnehmende mit aktiver Person in der Einheit.
    let phone: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case badge = "abzeichen"
        case role = "rolle"
        case imagePath = "bildUrl"
        case phone = "telefon"
    }
}

nonisolated struct UnitContact: Decodable, Sendable, Equatable {
    let contact: Contact?

    enum CodingKeys: String, CodingKey {
        case contact = "kontakt"
    }
}

nonisolated struct ProgramUnit: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case type = "typ"
    }
}

/// Eigene teilnehmende Person im Programm. `status`: `ja`, `nein` oder `nil` für offen.
nonisolated struct ProgramParticipant: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let firstName: String
    let status: String?
    let badge: Badge?

    enum CodingKeys: String, CodingKey {
        case id, status
        case firstName = "vorname"
        case badge = "abzeichen"
    }
}

/// Plätze der Leitenden bei einem Termin mit Höchstzahl (`leitungPlaetze`). Nur Zusagen belegen Plätze; Wartende haben keinen.
nonisolated struct LeaderSlots: Decodable, Sendable, Equatable {
    let maxCount: Int
    let taken: Int
    let free: Int
    let isFull: Bool
    let waiting: Int
    /// Nummer auf der Warteliste (1 = als Nächste dran); `nil`, wenn die Person nicht wartet.
    let ownPosition: Int?

    enum CodingKeys: String, CodingKey {
        case maxCount = "hoechstzahl"
        case taken = "belegt"
        case free = "frei"
        case isFull = "voll"
        case waiting = "wartende"
        case ownPosition = "eigenePosition"
    }

    init(maxCount: Int, taken: Int, free: Int, isFull: Bool, waiting: Int, ownPosition: Int?) {
        self.maxCount = maxCount
        self.taken = taken
        self.free = free
        self.isFull = isFull
        self.waiting = waiting
        self.ownPosition = ownPosition
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        maxCount = try values.decode(Int.self, forKey: .maxCount)
        taken = try values.decode(Int.self, forKey: .taken)
        free = try values.decode(Int.self, forKey: .free)
        isFull = try values.decode(Bool.self, forKey: .isFull)
        waiting = try values.decodeIfPresent(Int.self, forKey: .waiting) ?? 0
        ownPosition = try values.decodeIfPresent(Int.self, forKey: .ownPosition)
    }
}

/// Antwort auf `PUT …/leitung`: `status` ist `ja`, `nein` oder `warteliste` (bei vollem Termin setzt «ja» auf die Warteliste), `position` die Nummer dort.
/// Ein Server vor dieser Fassung antwortet 204 ohne Body.
nonisolated struct LeadershipResult: Decodable, Sendable, Equatable {
    let status: String
    let position: Int?
}

/// Listeneintrag und Detail (`ProgrammListeneintrag`, `ProgrammDetail`); `topic`, `info`, `callUp` und `contact` füllt nur das Detail.
/// `status`: `aktiv`, `abgesagt` oder `pruefen`. Ganztägig: `dayFrom`/`dayTo` gesetzt, sonst `start`/`end`.
nonisolated struct Program: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let status: String
    let isAllDay: Bool
    let start: Date?
    let end: Date?
    let dayFrom: SwissDay?
    let dayTo: SwissDay?
    let kind: String?
    let registrationFrom: SwissDay
    let isAttendanceOpen: Bool
    let unit: ProgramUnit
    let participants: [ProgramParticipant]
    /// Eigene Anmeldung als Leitung: `ja`, `nein` oder `offen`; fehlt, wenn die Person keine Rolle in der Einheit hat.
    /// `ja`, `nein`, `offen` oder `warteliste` (nur bei Terminen mit Höchstzahl für Leitende, Issue #66).
    let ownRegistration: String?
    /// Plätze für Leitende: nur bei selbst erstellten Terminen mit Höchstzahl und nur für Kommando und Leitung; sonst fehlt der Schlüssel.
    let leaderSlots: LeaderSlots?
    let topic: String?
    let info: String?
    let callUp: String?
    let contact: Contact?

    enum CodingKeys: String, CodingKey {
        case id, status, info
        case title = "titel"
        case isAllDay = "ganztaegig"
        case start = "beginn"
        case end = "ende"
        case dayFrom = "tagVon"
        case dayTo = "tagBis"
        case kind = "art"
        case registrationFrom = "anmeldungAb"
        case isAttendanceOpen = "teilnahmeOffen"
        case unit = "einheit"
        case participants = "teilnehmende"
        case ownRegistration = "eigeneAnmeldung"
        case leaderSlots = "leitungPlaetze"
        case topic = "thema"
        case callUp = "aufgebot"
        case contact = "kontakt"
    }
}

nonisolated struct ProgramList: Decodable, Sendable, Equatable {
    let programs: [Program]

    enum CodingKeys: String, CodingKey {
        case programs = "programme"
    }
}

nonisolated struct ParticipationCount: Decodable, Sendable, Equatable {
    let yes: Int
    let no: Int
    let open: Int
    /// Nur bei den Leitenden eines Termins mit Höchstzahl.
    let waitlist: Int

    enum CodingKeys: String, CodingKey {
        case yes = "ja"
        case no = "nein"
        case open = "offen"
        case waitlist = "warteliste"
    }

    init(yes: Int, no: Int, open: Int, waitlist: Int = 0) {
        self.yes = yes
        self.no = no
        self.open = open
        self.waitlist = waitlist
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        yes = try values.decode(Int.self, forKey: .yes)
        no = try values.decode(Int.self, forKey: .no)
        open = try values.decode(Int.self, forKey: .open)
        waitlist = try values.decodeIfPresent(Int.self, forKey: .waitlist) ?? 0
    }
}

/// `status` der Teilnehmenden und Leitenden: `ja`, `nein` oder `offen`.
nonisolated struct ParticipationEntry: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let firstName: String
    let lastName: String
    let status: String
    let badge: Badge?

    enum CodingKeys: String, CodingKey {
        case id, status
        case firstName = "vorname"
        case lastName = "nachname"
        case badge = "abzeichen"
    }
}

/// `role`: `kommandant`, `stellvertretung` oder `leitung`.
nonisolated struct LeaderParticipation: Decodable, Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let imagePath: String?
    let role: String
    /// `ja`, `nein`, `offen` oder `warteliste`.
    let status: String
    /// Nummer auf der Warteliste, nur bei `warteliste`.
    let position: Int?
    let badge: Badge?

    enum CodingKeys: String, CodingKey {
        case id, name, status, position
        case imagePath = "bildUrl"
        case role = "rolle"
        case badge = "abzeichen"
    }
}

/// `GET /api/v1/programme/{id}/teilnahmen`. Eltern und Teilnehmende sehen nur ihre eigenen Personen und keine Leitenden.
nonisolated struct Participations: Decodable, Sendable, Equatable {
    struct Counts: Decodable, Sendable, Equatable {
        let participants: ParticipationCount
        let leaders: ParticipationCount

        enum CodingKeys: String, CodingKey {
            case participants = "teilnehmende"
            case leaders = "leitende"
        }
    }

    let counts: Counts
    let participants: [ParticipationEntry]
    let leaders: [LeaderParticipation]
    /// Nur bei Terminen mit Höchstzahl, für Kommando und Leitung.
    let leaderSlots: LeaderSlots?

    enum CodingKeys: String, CodingKey {
        case leaderSlots = "leitungPlaetze"
        case counts = "zahlen"
        case participants = "teilnehmende"
        case leaders = "leitende"
    }
}

/// Antwort auf ein Programm: der Vertrag kennt «ja» und «nein» (es gibt kein Zurück auf «offen»).
nonisolated enum Answer: String, Encodable, Sendable {
    case yes = "ja"
    case no = "nein"
}

nonisolated struct AnswerRequest: Encodable, Sendable {
    let status: Answer
}

// MARK: Push

nonisolated struct PushTokenRequest: Encodable, Sendable {
    let token: String
    let plattform: String
}
