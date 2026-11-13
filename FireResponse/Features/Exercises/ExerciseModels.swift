import Foundation
import Observation

/// Bilder (Profilbilder, Rangabzeichen) im Arbeitsspeicher; sie verlassen die App nie. Ein Fehler lässt den Platzhalter stehen.
@MainActor @Observable
final class RemoteImages {
    private(set) var data: [String: Data] = [:]
    private var requested: Set<String> = []
    private let service: any ExercisesService

    init(service: any ExercisesService) { self.service = service }

    func loadPerson(_ path: String?) async {
        guard let path, requested.insert(path).inserted else { return }
        if let bytes = await service.personImage(path: path).value { data[path] = bytes }
    }

    /// Logos stehen unter `logoKey`; `settledLogos` hält fest, welche fertig sind (geladen oder ohne Logo), damit das Kürzel nicht kurz aufblitzt.
    private(set) var settledLogos: Set<String> = []

    nonisolated static func logoKey(_ unitId: String) -> String { "logo:" + unitId }

    func loadLogo(_ unit: ProgramUnit) async {
        let key = Self.logoKey(unit.id)
        guard requested.insert(key).inserted else { return }
        if let bytes = await service.unitLogo(unitId: unit.id).value { data[key] = bytes }
        settledLogos.insert(key)
    }

    func loadBadge(_ badge: Badge?) async {
        guard let path = badge?.imagePath, requested.insert(path).inserted else { return }
        if let bytes = await service.badgeImage(path: path).value { data[path] = bytes }
    }
}

/// Liste aller eigenen Übungen in einer Abfrage; die App schickt nie eine Einheit mit.
@MainActor @Observable
final class ExerciseListModel {
    enum Phase: Equatable {
        case loading
        case loaded([ProgramDay])
        case failed(ApiError)
    }

    /// Fenster der Abfrage ab heute.
    static let windowMonths = 6

    private(set) var phase: Phase = .loading
    /// Fehler eines Neuladens, während schon Daten da sind.
    private(set) var refreshError: ApiError?
    private let service: any ExercisesService
    private let now: @Sendable () -> Date
    private let onLoaded: @MainActor ([Program]) -> Void

    /// `onLoaded` bekommt jede frisch geladene Liste (die App füttert damit das Widget).
    init(service: any ExercisesService, now: @escaping @Sendable () -> Date = { .now }, onLoaded: @escaping @MainActor ([Program]) -> Void = { _ in }) {
        self.service = service
        self.now = now
        self.onLoaded = onLoaded
    }

    var today: SwissDay { SwissDay(date: now()) }

    func load() async {
        let from = today
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = SwissDay.timeZone
        let until = SwissDay(date: calendar.date(byAdding: .month, value: Self.windowMonths, to: ExerciseFormat.date(from)) ?? now())
        switch await service.programs(from: from, to: until) {
        case .ok(let list):
            refreshError = nil
            phase = .loaded(ExerciseRules.groupByDay(list.programs))
            onLoaded(list.programs)
        case .failure(let error, _, _):
            if case .loaded = phase { refreshError = error } else { phase = .failed(error) }
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }
}

/// Wen eine Antwort betrifft: eine teilnehmende Person oder die eigene Anmeldung als Leitung.
nonisolated enum AnswerTarget: Hashable {
    case participant(String)
    case leadership
}

/// Detail einer Übung: Laden, stilles Nachladen im Takt, Antworten.
@MainActor @Observable
final class ExerciseDetailModel {
    enum Phase: Equatable {
        case loading
        case loaded(Program)
        case failed(ApiError)
    }

    /// Eine laufende Antwort; solange sie läuft, sperrt jede weitere Aktion (globale Ladesperre).
    struct Saving: Equatable {
        let target: AnswerTarget
        let answer: Answer
    }

    /// Takt des stillen Nachladens, solange das Detail sichtbar ist.
    static let pollInterval: Duration = .seconds(30)

    let id: String
    private(set) var phase: Phase = .loading
    private(set) var saving: Saving?
    /// «Gesendet 12:10» je Person (Schlüssel `AnswerTarget`).
    private(set) var sentAt: [AnswerTarget: String] = [:]
    /// Zuletzt gesendete Antworten, falls das Neuladen danach scheitert; ein erfolgreiches Laden löscht sie.
    private(set) var localAnswers: [AnswerTarget: String] = [:]
    private(set) var error: ApiError?
    /// Zählt erfolgreiche Antworten (löst Haptik und Ansage aus).
    private(set) var sentCount = 0
    /// Zählt fehlgeschlagene Antworten (löst die Fehler-Haptik aus).
    private(set) var failedCount = 0
    private(set) var lastSentTime: String?
    /// Leitende mit Zusage und Wartende, nur bei Terminen mit Plätzen für Leitende (Issue #66).
    private(set) var leaders: [LeaderParticipation] = []
    /// Aktuelle Plätze aus der Teilnahmen-Liste; frischer als die aus dem Termin, sonst gleich.
    private(set) var leaderSlots: LeaderSlots?
    /// Die Person hat «ja» gesendet, der letzte Platz war aber schon weg: Sie steht auf der Warteliste (Alert).
    var placeTaken = false
    /// Von der Warteliste nachgerückt (zwischen zwei Ladungen von «warteliste» auf «ja»).
    var movedUp = false

    private let service: any ExercisesService
    private let now: @Sendable () -> Date

    init(id: String, service: any ExercisesService, now: @escaping @Sendable () -> Date = { .now }) {
        self.id = id
        self.service = service
        self.now = now
    }

    var today: SwissDay { SwissDay(date: now()) }

    func load() async {
        switch await service.program(id: id) {
        case .ok(let program):
            localAnswers = [:]
            apply(program)
            await loadLeaders()
        case .failure(let error, _, _):
            phase = .failed(error)
        }
    }

    /// Übernimmt das Programm. Wechselt die eigene Anmeldung von «warteliste» auf «ja», ist die Person nachgerückt.
    private func apply(_ program: Program) {
        if case .loaded(let before) = phase, before.ownRegistration == "warteliste", program.ownRegistration == "ja" { movedUp = true }
        phase = .loaded(program)
    }

    /// Die Leitenden mit Zusage und die Warteliste: nur, wenn der Termin Plätze für Leitende hat (der Schlüssel fehlt für alle anderen).
    /// Ein Fehler lässt die Liste leer; die Platzanzeige aus dem Termin bleibt.
    private func loadLeaders() async {
        guard case .loaded(let program) = phase, program.leaderSlots != nil else { leaders = []; leaderSlots = nil; return }
        if case .ok(let value) = await service.participations(programId: id) {
            leaders = value.leaders
            leaderSlots = value.leaderSlots
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }

    /// Stilles Nachladen: kein Ladezustand, ein Fehler lässt den alten Stand stehen, und während einer Antwort bleibt der Stand,
    /// den die Person gerade bestätigt.
    func refreshQuietly() async {
        guard saving == nil, case .loaded = phase else { return }
        if case .ok(let program) = await service.program(id: id), saving == nil {
            localAnswers = [:]
            apply(program)
            await loadLeaders()
        }
    }

    /// Antwort speichern, danach das Programm neu lesen: Der Server entscheidet über den Stand, auch über die Kontaktperson
    /// (wer absagt, gibt sie an die Stellvertretung ab).
    func answer(_ answer: Answer, for target: AnswerTarget) async {
        guard saving == nil, case .loaded = phase else { return }
        saving = Saving(target: target, answer: answer)
        error = nil
        placeTaken = false
        movedUp = false
        let slotsBefore: LeaderSlots?
        if case .loaded(let program) = phase { slotsBefore = leaderSlots ?? program.leaderSlots } else { slotsBefore = nil }
        var leadership: LeadershipResult?
        let result: ApiResult<Void>
        switch target {
        case .participant(let participantId): result = await service.setParticipation(programId: id, participantId: participantId, answer: answer)
        case .leadership:
            let sent = await service.setLeadership(programId: id, answer: answer)
            leadership = sent.value
            result = sent.map { _ in () }
        }
        switch result {
        case .ok:
            lastSentTime = ExerciseFormat.time(now())
            sentAt[target] = lastSentTime
            // Der Server entscheidet: bei vollem Termin macht «ja» eine Wartende.
            let status = leadership?.status ?? answer.rawValue
            localAnswers[target] = status
            // Rennen um den letzten Platz: Die Ansicht zeigte noch freie Plätze, die Antwort sagt «warteliste».
            if answer == .yes, status == "warteliste", slotsBefore?.isFull == false { placeTaken = true }
            sentCount += 1
            if case .ok(let program) = await service.program(id: id) {
                localAnswers = [:]
                phase = .loaded(program)
                await loadLeaders()
            }
        case .failure(let failure, _, _):
            error = failure
            failedCount += 1
        }
        saving = nil
    }

    /// Antwort einer Person: die gerade gespeicherte, sonst die lokal gesendete, sonst die des Servers.
    func status(of target: AnswerTarget, server: String?) -> String? {
        if let saving, saving.target == target { return saving.answer.rawValue }
        return localAnswers[target] ?? server
    }
}

/// Anmeldungen der Einheit, nur lesend.
@MainActor @Observable
final class RegistrationsModel {
    enum Phase: Equatable {
        case loading
        case loaded(Participations)
        case failed(ApiError)
    }

    let programId: String
    private(set) var phase: Phase = .loading
    private let service: any ExercisesService

    init(programId: String, service: any ExercisesService) {
        self.programId = programId
        self.service = service
    }

    func load() async {
        switch await service.participations(programId: programId) {
        case .ok(let value): phase = .loaded(value)
        case .failure(let error, _, _): phase = .failed(error)
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }
}
