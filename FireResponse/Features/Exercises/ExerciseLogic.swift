import Foundation

/// Netzzugriff der Übungen. `FireResponseAPI` erfüllt ihn; Tests setzen einen Fake ein.
nonisolated protocol ExercisesService: Sendable {
    func programs(from: SwissDay, to: SwissDay) async -> ApiResult<ProgramList>
    func program(id: String) async -> ApiResult<Program>
    func participations(programId: String) async -> ApiResult<Participations>
    func setParticipation(programId: String, participantId: String, answer: Answer) async -> ApiResult<Void>
    func setLeadership(programId: String, answer: Answer) async -> ApiResult<Void>
    func personImage(path: String) async -> ApiResult<Data>
    func badgeImage(path: String) async -> ApiResult<Data>
    func unitLogo(unitId: String) async -> ApiResult<Data>
}

extension FireResponseAPI: ExercisesService {}

nonisolated extension ParticipationCount {
    var total: Int { yes + no + open }
}

/// Alle Tage eines Programms, gruppiert; `day` ist `nil`, wenn der Server keine lesbare Zeit liefert.
nonisolated struct ProgramDay: Equatable, Identifiable {
    let day: SwissDay?
    let programs: [Program]
    var id: String { programs.first?.id ?? "leer" }
}

/// Wann sich antworten lässt (aus `isAttendanceOpen` und `registrationFrom` der API; `anmeldbar` gilt nicht mehr; die App rechnet das Fenster nicht selbst).
nonisolated enum RegistrationWindow: Equatable {
    case open
    case opensOn(SwissDay)
    case closed
}

/// Ein Monat der Zeitleiste; `heading` fehlt bei Tagen ohne lesbare Zeit.
nonisolated struct MonthSection: Equatable, Identifiable {
    let key: Int?
    let heading: String?
    var days: [ProgramDay]
    var id: String { key.map(String.init) ?? "ohne-zeit-\(days.first?.id ?? "")" }
}

nonisolated enum ExerciseRules {
    /// Der Tag, an dem die Übung beginnt (ganztägig `dayFrom`, sonst der Beginn in Schweizer Zeit).
    static func startDay(_ program: Program) -> SwissDay? {
        program.isAllDay ? program.dayFrom : program.start.map(SwissDay.init(date:))
    }

    /// Der Server sortiert nach Beginn; gleiche Tage liegen hintereinander und erscheinen in der Zeitleiste nur einmal.
    static func groupByDay(_ programs: [Program]) -> [ProgramDay] {
        var days: [ProgramDay] = []
        for program in programs {
            let day = startDay(program)
            if let last = days.last, last.day == day {
                days[days.count - 1] = ProgramDay(day: day, programs: last.programs + [program])
            } else {
                days.append(ProgramDay(day: day, programs: [program]))
            }
        }
        return days
    }

    /// Monate in der Reihenfolge des Servers. Ein Wechsel von Jahr oder Monat beginnt einen neuen Abschnitt; die Überschrift nennt das Jahr nur,
    /// wenn die vorige Überschrift in einem anderen Jahr lag (die erste nie). Tage ohne lesbare Zeit bilden einen Abschnitt ohne Überschrift.
    static func groupByMonth(_ days: [ProgramDay]) -> [MonthSection] {
        var sections: [MonthSection] = []
        var lastHeadingYear: Int?
        for day in days {
            let key = day.day.map { $0.year * 100 + $0.month }
            if let last = sections.last, last.key == key {
                sections[sections.count - 1].days.append(day)
                continue
            }
            var heading: String?
            if let first = day.day {
                heading = ExerciseFormat.monthHeading(first, withYear: lastHeadingYear.map { $0 != first.year } ?? false)
                lastHeadingYear = first.year
            }
            sections.append(MonthSection(key: key, heading: heading, days: [day]))
        }
        return sections
    }

    static func window(_ program: Program, today: SwissDay) -> RegistrationWindow {
        if program.isAttendanceOpen { return .open }
        if program.status == "aktiv", program.registrationFrom > today { return .opensOn(program.registrationFrom) }
        return .closed
    }

    /// Kommando, Leitende und das Konto des Kantonsadmins sehen die Anmeldungen der Einheit (nur lesend). Entscheiden tut der Server (403).
    static func canSeeRegistrations(_ program: Program, profile: Profile?) -> Bool {
        guard let profile else { return false }
        return profile.isCantonAdmin || profile.units.contains { $0.id == program.unit.id }
    }

    /// Offene zuerst (die braucht man), dann Ja, dann Nein; sonst in der Reihenfolge des Servers.
    static func sortedByStatus<T>(_ items: [T], status: (T) -> String) -> [T] {
        func rank(_ value: String) -> Int { value == "ja" ? 1 : value == "nein" ? 2 : 0 }
        return items.enumerated().sorted { (rank(status($0.element)), $0.offset) < (rank(status($1.element)), $1.offset) }.map(\.element)
    }

    /// Nur Ziffern und ein führendes «+»; leer, wenn nichts Wählbares übrig bleibt.
    static func dialString(_ phone: String) -> String? {
        let digits = phone.filter(\.isASCII).filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return (phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : "") + digits
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        return [parts.first, parts.count > 1 ? parts.last : nil].compactMap { $0?.first }.map(String.init).joined().uppercased()
    }
}

/// Anzeige von Datum und Zeit in Schweizer Zeit und `de_CH`.
nonisolated enum ExerciseFormat {
    static let locale = Locale(identifier: "de_CH")

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = SwissDay.timeZone
        return calendar
    }

    /// Mittag des Kalendertags: sicher gegen Zeitumstellungen.
    static func date(_ day: SwissDay) -> Date {
        calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? .distantPast
    }

    private static func style(_ format: Date.FormatStyle) -> Date.FormatStyle {
        var style = format.locale(locale)
        style.timeZone = SwissDay.timeZone
        return style
    }

    /// «SA»
    static func weekdayShort(_ day: SwissDay) -> String {
        date(day).formatted(style(.dateTime.weekday(.abbreviated))).replacingOccurrences(of: ".", with: "").uppercased(with: locale)
    }

    /// «Samstag, 14. November», mit Jahr «Samstag, 14. November 2027»
    static func longDay(_ day: SwissDay, withYear: Bool = false) -> String {
        date(day).formatted(style(withYear ? .dateTime.weekday(.wide).day().month(.wide).year() : .dateTime.weekday(.wide).day().month(.wide)))
    }

    /// «14. November»
    static func dayAndMonth(_ day: SwissDay) -> String {
        date(day).formatted(style(.dateTime.day().month(.wide)))
    }

    /// «November», mit Jahr «Januar 2027»
    static func monthHeading(_ day: SwissDay, withYear: Bool) -> String {
        date(day).formatted(style(withYear ? .dateTime.month(.wide).year() : .dateTime.month(.wide)))
    }

    /// «14.11.»
    static func numeric(_ day: SwissDay) -> String { "\(day.day).\(day.month)." }

    /// «SA 14.11.» für Zusatzzeilen
    static func shortDay(_ day: SwissDay) -> String { "\(weekdayShort(day)) \(numeric(day))" }

    static func time(_ date: Date) -> String {
        date.formatted(style(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
    }

    /// «14:00–17:00»; über mehrere Tage nur der Beginn; ganztägig «Ganztägig» bzw. «Ganztägig bis 16.11.».
    static func timeText(_ program: Program) -> String {
        if program.isAllDay {
            guard let from = program.dayFrom, let until = program.dayTo else { return String(localized: "Zeit noch offen") }
            if from == until { return String(localized: "Ganztägig") }
            return String(localized: "Ganztägig bis \(numeric(until))")
        }
        guard let start = program.start, let end = program.end else { return String(localized: "Zeit noch offen") }
        return SwissDay(date: start) == SwissDay(date: end) ? "\(time(start))–\(time(end))" : time(start)
    }

    /// Für VoiceOver: «14 bis 17 Uhr».
    static func spokenTime(_ program: Program) -> String {
        guard !program.isAllDay, let start = program.start, let end = program.end, SwissDay(date: start) == SwissDay(date: end) else {
            return timeText(program)
        }
        func part(_ date: Date) -> String {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (parts.minute ?? 0) == 0 ? "\(parts.hour ?? 0)" : time(date)
        }
        return String(localized: "\(part(start)) bis \(part(end)) Uhr")
    }

    /// Die Zeit für die Detailansicht in zwei Zeilen: oben die Uhrzeit, darunter das Datum ausgeschrieben (Schweizer Zeit).
    /// Das Jahr steht nur, wenn es nicht das laufende ist; geht die Übung über einen Jahreswechsel, steht es bei beiden Daten.
    /// `nil`, wenn der Server keine lesbare Zeit liefert.
    struct TimeDisplay: Equatable {
        let time: String
        let date: String
        /// Ein Satz für VoiceOver.
        let spoken: String
    }

    static func timeDisplay(_ program: Program, today: SwissDay = SwissDay(date: .now)) -> TimeDisplay? {
        func day(_ value: SwissDay, _ sameYearSpan: Bool = false) -> String { longDay(value, withYear: value.year != today.year || sameYearSpan) }
        if program.isAllDay {
            guard let from = program.dayFrom, let until = program.dayTo else { return nil }
            let label = String(localized: "Ganztägig")
            if from == until {
                let text = day(from)
                return TimeDisplay(time: label, date: text, spoken: String(localized: "Zeit: \(label), \(text)"))
            }
            let span = from.year != until.year
            let text = String(localized: "\(day(from, span)) bis \(day(until, span))")
            return TimeDisplay(time: label, date: text, spoken: String(localized: "Zeit: \(label), von \(day(from, span)) bis \(day(until, span))"))
        }
        guard let start = program.start, let end = program.end else { return nil }
        let first = SwissDay(date: start)
        let last = SwissDay(date: end)
        if first == last {
            let text = day(first)
            return TimeDisplay(
                time: "\(time(start))–\(time(end))", date: text,
                spoken: String(localized: "Zeit: \(text), \(time(start)) bis \(time(end)) Uhr")
            )
        }
        let span = first.year != last.year
        return TimeDisplay(
            time: "\(time(start)) – \(time(end))",
            date: String(localized: "\(day(first, span)) bis \(day(last, span))"),
            spoken: String(localized: "Zeit: \(day(first, span)), \(time(start)) bis \(day(last, span)), \(time(end)) Uhr")
        )
    }

    /// Der Stand je Person als Satz («Noah kommt», «Zusage für Lena offen»), danach der eigene als Leitung.
    static func statusSentences(_ program: Program) -> [(symbol: String, text: String, kind: StatusKind)] {
        guard program.status != "abgesagt" else { return [] }
        let people = program.participants.map { person -> (String, String, StatusKind) in
            switch person.status {
            case "ja": ("checkmark", String(localized: "\(person.firstName) kommt"), .yes)
            case "nein": ("xmark", String(localized: "\(person.firstName) kommt nicht"), .no)
            default: ("questionmark.circle", String(localized: "Zusage für \(person.firstName) offen"), .open)
            }
        }
        let own: [(String, String, StatusKind)] = program.ownRegistration.map {
            switch $0 {
            case "ja": [("checkmark", String(localized: "Du bist dabei"), .yes)]
            case "nein": [("xmark", String(localized: "Du bist nicht dabei"), .no)]
            default: [("questionmark.circle", String(localized: "Anmeldung offen"), .open)]
            }
        } ?? []
        return (people + own).map { (symbol: $0.0, text: $0.1, kind: $0.2) }
    }

    /// Der volle Satz der Karte für VoiceOver.
    static func cardSentence(_ program: Program, today: SwissDay) -> String {
        var parts: [String?] = [startDay(program).map { longDay($0) }, spokenTime(program), program.title, program.unit.name]
        if program.status == "abgesagt" { parts.append(String(localized: "Abgesagt")) }
        if program.status == "pruefen" { parts.append(String(localized: "Wird noch geprüft")) }
        parts += statusSentences(program).map(\.text)
        if case .opensOn(let day) = ExerciseRules.window(program, today: today) { parts.append(opensOnText(day)) }
        return parts.compactMap { $0 }.joined(separator: ", ")
    }

    static func opensOnText(_ day: SwissDay) -> String {
        String(localized: "Anmeldung ab \(dayAndMonth(day))")
    }

    private static func startDay(_ program: Program) -> SwissDay? { ExerciseRules.startDay(program) }

    enum StatusKind { case yes, no, open }
}

/// Texte zu den Fehlern der API; nie der Text des Servers.
nonisolated enum ExerciseMessage {
    static func text(for error: ApiError) -> LocalizedStringResource {
        switch error {
        case .notSignedIn: "Du bist nicht angemeldet. Bitte melde dich an."
        case .forbidden: "Das darfst du nicht."
        case .notFound: "Das gibt es nicht mehr, oder du darfst es nicht sehen."
        case .appOutdated: "Diese App ist zu alt. Bitte installiere die neue Version."
        case .tooManyRequests: "Zu viele Anfragen. Bitte warte einen Moment und versuche es dann nochmals."
        case .registrationClosed: "Die Anmeldung ist geschlossen. Die Übung ist abgesagt oder hat schon begonnen."
        case .registrationNotOpen: "Die Anmeldung ist noch nicht offen."
        case .appointmentStarted: "Die Übung hat schon begonnen. Die Anmeldung lässt sich nicht mehr ändern."
        case .network: "Keine Verbindung. Prüfe dein Internet und versuche es nochmals."
        case .unknown: "Etwas ist schiefgelaufen. Bitte versuche es nochmals."
        }
    }
}
