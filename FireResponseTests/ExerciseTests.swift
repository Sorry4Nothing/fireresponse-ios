import Foundation
import os
import Testing
@testable import FireResponse

/// Fake des Netzes; Beispieldaten sind erfunden.
final class FakeExercises: ExercisesService, @unchecked Sendable {
    struct State {
        var program: Program
        var participationResult: ApiResult<Void> = .ok(())
        var leadershipResult: ApiResult<Void> = .ok(())
        var programCalls = 0
        var setCalls: [String] = []
        var reloadFails = false
    }

    let state: OSAllocatedUnfairLock<State>

    init(_ program: Program) { state = OSAllocatedUnfairLock(initialState: State(program: program)) }

    func programs(from: SwissDay, to: SwissDay) async -> ApiResult<ProgramList> { .ok(ProgramList(programs: [state.withLock { $0.program }])) }

    func program(id: String) async -> ApiResult<Program> {
        state.withLock {
            $0.programCalls += 1
            return $0.reloadFails ? .failure(.network) : .ok($0.program)
        }
    }

    func participations(programId: String) async -> ApiResult<Participations> { .failure(.forbidden) }

    func setParticipation(programId: String, participantId: String, answer: Answer) async -> ApiResult<Void> {
        state.withLock {
            $0.setCalls.append("\(participantId)=\(answer.rawValue)")
            return $0.participationResult
        }
    }

    func setLeadership(programId: String, answer: Answer) async -> ApiResult<Void> {
        state.withLock {
            $0.setCalls.append("leitung=\(answer.rawValue)")
            return $0.leadershipResult
        }
    }

    func personImage(path: String) async -> ApiResult<Data> { .failure(.notFound) }
    func badgeImage(path: String) async -> ApiResult<Data> { .failure(.notFound) }
    func unitLogo(unitId: String) async -> ApiResult<Data> { .failure(.notFound) }
}

nonisolated func makeProgram(
    id: String = "p1", start: String = "2027-03-06T13:00:00.000Z", end: String = "2027-03-06T16:00:00.000Z", status: String = "aktiv",
    registrationFrom: String = "2027-01-23", open: Bool = true, own: String? = nil,
    participantStatus: String? = nil, contactName: String = "Erika Muster"
) throws -> Program {
    let ownJSON = own.map { #""eigeneAnmeldung":"\#($0)","# } ?? ""
    let participantJSON = participantStatus.map { #""\#($0)""# } ?? "null"
    let json = """
    {"id":"\(id)","titel":"Schläuche kuppeln","status":"\(status)","ganztaegig":false,"beginn":"\(start)","ende":"\(end)",
     "art":"Übung","anmeldbar":true,"anmeldungAb":"\(registrationFrom)","teilnahmeOffen":\(open),
     "einheit":{"id":"e1","name":"JF Beispielstadt","typ":"jf"},\(ownJSON)
     "teilnehmende":[{"id":"t1","vorname":"Anna","status":\(participantJSON),"abzeichen":null}],
     "kontakt":{"id":"k1","name":"\(contactName)","rolle":"kommandant","bildUrl":null,"abzeichen":null}}
    """
    return try JSONDecoder.api.decode(Program.self, from: Data(json.utf8))
}

@MainActor
struct ExerciseTests {
    @Test func oldServerAnmeldbarFalseDoesNotChangeTheWindow() throws {
        let json = #"{"id":"p","titel":"T","status":"aktiv","ganztaegig":false,"beginn":"2027-03-06T13:00:00.000Z","ende":"2027-03-06T16:00:00.000Z","# +
            #""art":null,"anmeldbar":false,"anmeldungAb":"2027-02-10","teilnahmeOffen":false,"einheit":{"id":"e1","name":"JF","typ":"jf"},"teilnehmende":[]}"#
        let program = try JSONDecoder.api.decode(Program.self, from: Data(json.utf8))
        #expect(ExerciseRules.window(program, today: try #require(SwissDay("2027-02-01"))) == .opensOn(try #require(SwissDay("2027-02-10"))))
    }

    @Test func cardSentenceNamesTheUnit() throws {
        let program = try makeProgram()
        let today = try #require(SwissDay("2027-03-01"))
        #expect(ExerciseFormat.cardSentence(program, today: today).contains("JF Beispielstadt"))
    }

    let today = SwissDay("2027-02-01") ?? SwissDay(date: .now)

    @Test func windowOpensOnRegistrationFrom() throws {
        let early = try makeProgram(registrationFrom: "2027-02-10", open: false)
        #expect(ExerciseRules.window(early, today: today) == .opensOn(SwissDay("2027-02-10") ?? today))
        let open = try makeProgram(registrationFrom: "2027-01-23", open: true)
        #expect(ExerciseRules.window(open, today: today) == .open)
        // Fenster vorbei (begonnen): geschlossen, kein «ab»-Datum. `anmeldbar` zählt nicht mehr (alter Server: `false`).
        #expect(ExerciseRules.window(try makeProgram(registrationFrom: "2027-01-01", open: false), today: today) == .closed)
        #expect(ExerciseRules.window(try makeProgram(status: "abgesagt", registrationFrom: "2027-02-10", open: false), today: today) == .closed)
    }

    @Test func answerSavesThenReloadsIncludingContact() async throws {
        let fake = FakeExercises(try makeProgram())
        let model = ExerciseDetailModel(id: "p1", service: fake)
        await model.load()
        fake.state.withLock { $0.program = (try? makeProgram(participantStatus: "ja", contactName: "Hans Probe")) ?? $0.program }
        await model.answer(.yes, for: .participant("t1"))
        guard case .loaded(let program) = model.phase else { Issue.record("nicht geladen"); return }
        #expect(fake.state.withLock { $0.setCalls } == ["t1=ja"])
        #expect(fake.state.withLock { $0.programCalls } == 2)
        #expect(program.participants.first?.status == "ja" && program.contact?.name == "Hans Probe")
        #expect(model.saving == nil && model.error == nil && model.sentAt[.participant("t1")] != nil && model.sentCount == 1)
    }

    @Test func answerSurvivesFailedReload() async throws {
        let fake = FakeExercises(try makeProgram())
        let model = ExerciseDetailModel(id: "p1", service: fake)
        await model.load()
        fake.state.withLock { $0.reloadFails = true }
        await model.answer(.no, for: .participant("t1"))
        #expect(model.status(of: .participant("t1"), server: nil) == "nein")
    }

    @Test func conflictsMapToFriendlyErrorsAndKeepOldState() async throws {
        let fake = FakeExercises(try makeProgram(participantStatus: "ja"))
        let model = ExerciseDetailModel(id: "p1", service: fake)
        await model.load()
        for (code, expected) in [("PROGRAMM_BEGONNEN", ApiError.appointmentStarted), ("ANMELDEFENSTER_NICHT_OFFEN", .registrationNotOpen),
                                 ("PROGRAMM_GESCHLOSSEN", .registrationClosed)] {
            #expect(ApiError.from(status: 409, code: code) == expected)
            fake.state.withLock { $0.leadershipResult = .failure(expected) }
            await model.answer(.no, for: .leadership)
            #expect(model.error == expected && model.saving == nil)
            #expect(String(localized: ExerciseMessage.text(for: expected)).isEmpty == false)
        }
        #expect(model.status(of: .participant("t1"), server: "ja") == "ja")
        #expect(fake.state.withLock { $0.programCalls } == 1)
    }

    @Test func quietRefreshKeepsStateOnFailure() async throws {
        let fake = FakeExercises(try makeProgram())
        let model = ExerciseDetailModel(id: "p1", service: fake)
        await model.load()
        fake.state.withLock { $0.reloadFails = true }
        await model.refreshQuietly()
        if case .loaded = model.phase {} else { Issue.record("Stand verloren") }
    }

    @Test func groupsByDayInSwissTime() throws {
        // 23:30 UTC am 6.3. ist in Zürich schon der 7.3.
        let late = try makeProgram(id: "a", start: "2027-03-06T23:30:00.000Z", end: "2027-03-07T00:30:00.000Z")
        let early = try makeProgram(id: "b", start: "2027-03-07T08:00:00.000Z", end: "2027-03-07T09:00:00.000Z")
        let next = try makeProgram(id: "c", start: "2027-03-08T08:00:00.000Z", end: "2027-03-08T09:00:00.000Z")
        let days = ExerciseRules.groupByDay([late, early, next])
        #expect(days.map(\.programs.count) == [2, 1])
        #expect(days.first?.day?.description == "2027-03-07")
    }

    @Test func formatsInDeCH() throws {
        let program = try makeProgram()
        let day = try #require(SwissDay("2027-03-06"))
        #expect(ExerciseFormat.timeText(program) == "14:00–17:00")
        #expect(ExerciseFormat.spokenTime(program) == "14 bis 17 Uhr")
        #expect(ExerciseFormat.longDay(day) == "Samstag, 6. März")
        #expect(ExerciseFormat.weekdayShort(day) == "SA")
        #expect(ExerciseFormat.numeric(day) == "6.3.")
    }

    @Test func registrationsOnlyForLeadershipOfTheUnit() throws {
        let program = try makeProgram()
        func profile(unit: String, admin: Bool) throws -> Profile {
            try JSONDecoder.api.decode(Profile.self, from: Data("""
            {"id":"u1","name":"Erika Muster","benutzername":"e","kantonsadmin":\(admin),"zweiterFaktor":false,"einwilligung":true,
             "mussPasswortAendern":false,"pushProgramme":true,
             "einheiten":[{"id":"\(unit)","name":"JF","typ":"jf","bezirk":"B","rolle":"leitung","abzeichen":null}],"teilnehmende":[]}
            """.utf8))
        }
        #expect(ExerciseRules.canSeeRegistrations(program, profile: try profile(unit: "e1", admin: false)))
        #expect(!ExerciseRules.canSeeRegistrations(program, profile: try profile(unit: "e2", admin: false)))
        #expect(ExerciseRules.canSeeRegistrations(program, profile: try profile(unit: "e2", admin: true)))
        #expect(!ExerciseRules.canSeeRegistrations(program, profile: nil))
    }

    @Test func registrationsSortedOpenYesNo() {
        let sorted = ExerciseRules.sortedByStatus(["ja", "nein", "offen", "ja", "offen"], status: { $0 })
        #expect(sorted == ["offen", "offen", "ja", "ja", "nein"])
    }

    @Test func dialStringKeepsOnlyDialable() {
        #expect(ExerciseRules.dialString("+41 79 000 00 00") == "+41790000000")
        #expect(ExerciseRules.dialString("abc") == nil)
    }

    @Test func registrationsViewIsReadOnly() async throws {
        let fake = FakeExercises(try makeProgram())
        let model = RegistrationsModel(programId: "p1", service: fake)
        await model.load()
        #expect(model.phase == .failed(.forbidden))
        #expect(fake.state.withLock { $0.setCalls }.isEmpty)
    }
}
