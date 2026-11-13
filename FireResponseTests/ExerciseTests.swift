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
        /// Was der Server als Antwort auf die Leitungs-Zusage sagt; ohne Angabe gilt, was gesendet wurde (Server vor Nr. 34).
        var leadershipOutcome: LeadershipResult?
        /// Antwort der Teilnahmen-Liste (Leitende mit Zusage und Warteliste); ohne Angabe 403 wie für Eltern.
        var participationsValue: Participations?
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

    func participations(programId: String) async -> ApiResult<Participations> {
        state.withLock { $0.participationsValue.map { .ok($0) } ?? .failure(.forbidden) }
    }

    func setParticipation(programId: String, participantId: String, answer: Answer) async -> ApiResult<Void> {
        state.withLock {
            $0.setCalls.append("\(participantId)=\(answer.rawValue)")
            return $0.participationResult
        }
    }

    func setLeadership(programId: String, answer: Answer) async -> ApiResult<LeadershipResult> {
        state.withLock { current in
            current.setCalls.append("leitung=\(answer.rawValue)")
            let outcome = current.leadershipOutcome ?? LeadershipResult(status: answer.rawValue, position: nil)
            return current.leadershipResult.map { _ in outcome }
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
            #expect(model.failedCount > 0)
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

    @Test func monthHeadingsNameTheYearOnlyAtTheYearChange() throws {
        func program(_ id: String, _ iso: String) throws -> Program { try makeProgram(id: id, start: iso, end: iso) }
        let days = ExerciseRules.groupByDay([
            try program("a", "2026-11-14T10:00:00.000Z"), try program("b", "2026-11-20T10:00:00.000Z"),
            try program("c", "2026-12-05T10:00:00.000Z"), try program("d", "2027-01-09T10:00:00.000Z"),
            try program("e", "2027-02-06T10:00:00.000Z"),
        ])
        let sections = ExerciseRules.groupByMonth(days)
        #expect(sections.map(\.heading) == ["November", "Dezember", "Januar 2027", "Februar"])
        #expect(sections.map(\.days.count) == [2, 1, 1, 1])
    }

    @Test func daysWithoutTimeFormAnUntitledSection() throws {
        let timeless = ProgramDay(day: nil, programs: [try makeProgram(id: "x")])
        let sections = ExerciseRules.groupByMonth([timeless])
        #expect(sections.count == 1 && sections[0].heading == nil)
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

/// Zeit in der Detailansicht (Issue #35).
extension ExerciseTests {
    private func decoded(_ fields: String) throws -> Program {
        let json = #"{"id":"p","titel":"T","status":"aktiv",\#(fields),"# +
            #""art":null,"anmeldbar":true,"anmeldungAb":"2027-01-01","teilnahmeOffen":false,"einheit":{"id":"e1","name":"JF","typ":"jf"},"teilnehmende":[]}"#
        return try JSONDecoder.api.decode(Program.self, from: Data(json.utf8))
    }

    @Test func timeDisplayForOneDayMultipleDaysAndAllDay() throws {
        let today = try #require(SwissDay("2027-03-01"))
        let one = try #require(ExerciseFormat.timeDisplay(try makeProgram(), today: today))
        #expect(one.time == "14:00–17:00" && one.date == "Samstag, 6. März")
        #expect(one.spoken == "Zeit: Samstag, 6. März, 14:00 bis 17:00 Uhr")

        let night = try decoded(#""ganztaegig":false,"beginn":"2027-03-06T21:00:00.000Z","ende":"2027-03-07T01:00:00.000Z""#)
        let multi = try #require(ExerciseFormat.timeDisplay(night, today: today))
        #expect(multi.time == "22:00 – 02:00" && multi.date == "Samstag, 6. März bis Sonntag, 7. März")

        let allDay = try decoded(#""ganztaegig":true,"tagVon":"2027-03-06","tagBis":"2027-03-07""#)
        let all = try #require(ExerciseFormat.timeDisplay(allDay, today: today))
        #expect(all.time == "Ganztägig" && all.date == "Samstag, 6. März bis Sonntag, 7. März")
        let single = try decoded(#""ganztaegig":true,"tagVon":"2027-03-06","tagBis":"2027-03-06""#)
        #expect(ExerciseFormat.timeDisplay(single, today: today)?.date == "Samstag, 6. März")
    }

    @Test func timeDisplayNamesTheYearOnlyWhenItIsNotThisYear() throws {
        let next = try #require(SwissDay("2026-12-01"))
        #expect(ExerciseFormat.timeDisplay(try makeProgram(), today: next)?.date == "Samstag, 6. März 2027")
        let newYear = try decoded(#""ganztaegig":true,"tagVon":"2026-12-31","tagBis":"2027-01-01""#)
        #expect(ExerciseFormat.timeDisplay(newYear, today: next)?.date == "Donnerstag, 31. Dezember 2026 bis Freitag, 1. Januar 2027")
    }

    @Test func timeDisplayIsNilWithoutReadableTime() throws {
        let program = try decoded(#""ganztaegig":false,"beginn":null,"ende":null"#)
        #expect(ExerciseFormat.timeDisplay(program) == nil)
    }

    // MARK: Plätze für Leitende und Warteliste (Issue #66)

    private func slotsProgram(free: Int, full: Bool, own: String?, position: Int? = nil) throws -> Program {
        let ownJSON = own.map { #","eigeneAnmeldung":"\#($0)""# } ?? ""
        let slots = #","leitungPlaetze":{"hoechstzahl":4,"belegt":\#(4 - free),"frei":\#(free),"voll":\#(full),"wartende":1,"eigenePosition":\#(position.map(String.init) ?? "null")}"#
        return try decoded(#""ganztaegig":false,"beginn":"2027-03-06T13:00:00.000Z","ende":"2027-03-06T16:00:00.000Z"\#(slots)\#(ownJSON)"#)
    }

    @Test func slotsTextsAreCalmAndExact() throws {
        let two = try #require(try slotsProgram(free: 2, full: false, own: "offen").leaderSlots)
        #expect(LeaderSlotsText.line(two, own: "offen").text == "Noch 2 Plätze frei")
        let one = try #require(try slotsProgram(free: 1, full: false, own: "offen").leaderSlots)
        #expect(LeaderSlotsText.line(one, own: "offen").text == "Noch 1 Platz frei")
        let full = try #require(try slotsProgram(free: 0, full: true, own: "offen").leaderSlots)
        let fullLine = LeaderSlotsText.line(full, own: "offen")
        #expect(fullLine.text == "Voll" && fullLine.spoken == "Voll, Warteliste möglich" && fullLine.kind == .full)
        let waiting = try #require(try slotsProgram(free: 0, full: true, own: "warteliste", position: 2).leaderSlots)
        let waitingLine = LeaderSlotsText.line(waiting, own: "warteliste")
        #expect(waitingLine.text == "Warteliste, Platz 2" && waitingLine.kind == .waiting)
        #expect(LeaderSlotsText.waitingText(0) == nil && LeaderSlotsText.waitingText(1) == "1 auf der Warteliste" && LeaderSlotsText.waitingText(3) == "3 auf der Warteliste")
    }

    @Test func slotsKeyIsAbsentForEveryoneElse() throws {
        #expect(try makeProgram().leaderSlots == nil)
        #expect(try slotsProgram(free: 0, full: true, own: "warteliste", position: 1).ownRegistration == "warteliste")
    }

    @Test func raceForTheLastPlaceShowsTheAlert() async throws {
        let fake = FakeExercises(try slotsProgram(free: 1, full: false, own: "offen"))
        fake.state.withLock { $0.leadershipOutcome = LeadershipResult(status: "warteliste", position: 1) }
        let model = ExerciseDetailModel(id: "p", service: fake)
        await model.load()
        await model.answer(.yes, for: .leadership)
        #expect(model.placeTaken && model.error == nil)
    }

    @Test func joiningTheWaitlistOfAFullTermIsNoRaceAndNoError() async throws {
        let fake = FakeExercises(try slotsProgram(free: 0, full: true, own: "offen"))
        fake.state.withLock { $0.leadershipOutcome = LeadershipResult(status: "warteliste", position: 2) }
        let model = ExerciseDetailModel(id: "p", service: fake)
        await model.load()
        await model.answer(.yes, for: .leadership)
        #expect(!model.placeTaken && model.error == nil && model.sentCount == 1)
    }

    @Test func movingUpFromTheWaitlistIsNoticed() async throws {
        let fake = FakeExercises(try slotsProgram(free: 0, full: true, own: "warteliste", position: 1))
        let model = ExerciseDetailModel(id: "p", service: fake)
        await model.load()
        #expect(!model.movedUp)
        let promoted = try slotsProgram(free: 0, full: true, own: "ja")
        fake.state.withLock { $0.program = promoted }
        await model.refreshQuietly()
        #expect(model.movedUp)
    }

    @Test func leadersAndWaitlistLoadOnlyWithSlots() async throws {
        let json = #"{"zahlen":{"teilnehmende":{"ja":0,"nein":0,"offen":0},"leitende":{"ja":1,"nein":0,"offen":0,"warteliste":1}},"teilnehmende":[],"# +
            #""leitungPlaetze":{"hoechstzahl":1,"belegt":1,"frei":0,"voll":true,"wartende":1,"eigenePosition":null},"# +
            #""leitende":[{"id":"l1","name":"A","rolle":"leitung","status":"ja","bildUrl":null,"abzeichen":null},"# +
            #"{"id":"l2","name":"B","rolle":"leitung","status":"warteliste","position":1,"bildUrl":null,"abzeichen":null}]}"#
        let value = try JSONDecoder.api.decode(Participations.self, from: Data(json.utf8))
        #expect(value.counts.leaders.waitlist == 1 && value.leaders[1].position == 1 && value.leaderSlots?.isFull == true)

        let withSlots = FakeExercises(try slotsProgram(free: 0, full: true, own: "ja"))
        withSlots.state.withLock { $0.participationsValue = value }
        let model = ExerciseDetailModel(id: "p", service: withSlots)
        await model.load()
        #expect(model.leaders.count == 2 && model.leaderSlots?.waiting == 1)

        let without = FakeExercises(try makeProgram())
        without.state.withLock { $0.participationsValue = value }
        let plain = ExerciseDetailModel(id: "p", service: without)
        await plain.load()
        #expect(plain.leaders.isEmpty && plain.leaderSlots == nil)
    }

    @Test func waitlistedLeadersSortBetweenYesAndNo() {
        let sorted = ExerciseRules.sortedByStatus(["nein", "warteliste", "ja", "offen"], status: { $0 })
        #expect(sorted == ["offen", "ja", "warteliste", "nein"])
    }

    @Test func widgetShowsOnlyFullOrWaitlist() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2027-03-01T10:00:00+01:00"))
        let full = WidgetSnapshot.make(from: [try slotsProgram(free: 0, full: true, own: "ja")], now: now).rows.first
        #expect(full?.count == "Voll")
        let waiting = WidgetSnapshot.make(from: [try slotsProgram(free: 0, full: true, own: "warteliste", position: 2)], now: now).rows.first
        #expect(waiting?.count == "Warteliste")
        let free = WidgetSnapshot.make(from: [try slotsProgram(free: 2, full: false, own: "ja")], now: now).rows.first
        #expect(free?.count != "Voll" && free?.count != "Warteliste")
    }
}
