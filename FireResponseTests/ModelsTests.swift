import Foundation
import os
import Testing
@testable import FireResponse

/// Beispieldaten sind erfunden und folgen den Beispielen des Vertrags.
struct ModelsTests {
    func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder.api.decode(T.self, from: Data(json.utf8))
    }

    @Test func swissDay() throws {
        #expect(SwissDay("2027-03-01")?.description == "2027-03-01")
        #expect(SwissDay("2027-02-30") == nil)
        #expect(SwissDay("27-3-1") == nil)
        #expect(try #require(SwissDay("2027-03-01")) < #require(SwissDay("2027-03-02")))
        // 23:30 UTC ist in Zürich schon der nächste Tag.
        let late = try #require(ISO8601DateFormatter().date(from: "2027-03-01T23:30:00Z"))
        #expect(SwissDay(date: late).description == "2027-03-02")
    }

    @Test func signInWithSessionAndWithSecondFactor() throws {
        let ok: SignInResponse = try decode(#"{"redirect":false,"token":"t","user":{"id":"u1","name":"Erika Muster","extra":1}}"#)
        #expect(!ok.needsSecondFactor && ok.user?.mustChangePassword == false)
        let second: SignInResponse = try decode(#"{"twoFactorRedirect":true,"twoFactorMethods":["totp"]}"#)
        #expect(second.needsSecondFactor && second.user == nil)
    }

    @Test func sessionMayBeNull() throws {
        #expect(try decode("null", as: AuthSession?.self) == nil)
        let session: AuthSession? = try decode(
            #"{"session":{"id":"s","userId":"u1","expiresAt":"2027-02-01T10:00:00.000Z"},"user":{"id":"u1","name":"Erika Muster","mussPasswortAendern":true}}"#
        )
        #expect(session?.user.mustChangePassword == true)
    }

    @Test func profile() throws {
        let profile: Profile = try decode("""
        {"id":"u1","name":"Erika Muster","benutzername":"erika.muster","kantonsadmin":false,"zweiterFaktor":false,"einwilligung":true,
         "mussPasswortAendern":false,"telefon":null,"bildUrl":"/api/v1/personen/u1/bild?v=2","pushProgramme":true,
         "einheiten":[{"id":"e1","name":"JF Beispielstadt","typ":"jf","bezirk":"Bezirk Beispiel","rolle":"leitung",
                       "logoUrl":null,"abzeichen":{"kuerzel":"Oblt","sterne":null,"bildUrl":"/api/v1/raenge/r1/abzeichen"}}],
         "teilnehmende":[{"id":"t1","vorname":"Max","nachname":"Beispiel","einheitId":"e1","einheitName":"JF Beispielstadt","einheitTyp":"jf","art":"eltern","abzeichen":null}]}
        """)
        #expect(profile.username == "erika.muster" && profile.pushRegistrations == nil && profile.phone == nil)
        #expect(profile.units.first?.badge?.abbreviation == "Oblt")
        #expect(profile.units.first?.badge?.imagePath == "/api/v1/raenge/r1/abzeichen")
        #expect(profile.participants.first?.unitId == "e1" && profile.participants.first?.badge == nil)
        #expect(profile.participants.first?.unitName == "JF Beispielstadt" && profile.participants.first?.unitType == "jf")
        // Ein Server vor dieser Fassung nennt Name und Typ der Einheit nicht: die Zeile bleibt schlicht.
        let old = #"{"id":"t","vorname":"Max","nachname":"B","einheitId":"e1","art":"eltern","abzeichen":null}"#
        let oldParticipant = try JSONDecoder.api.decode(ProfileParticipant.self, from: Data(old.utf8))
        #expect(oldParticipant.unitName == nil && oldParticipant.unitType == nil)
    }

    @Test func programDetailWithAllDayAndTimed() throws {
        let timed: Program = try decode("""
        {"id":"p1","titel":"Übung Knoten","status":"aktiv","ganztaegig":false,"beginn":"2027-03-01T17:00:00.000Z","ende":"2027-03-01T19:00:00Z",
         "tagVon":null,"tagBis":null,"art":"Übung","anmeldbar":true,"anmeldungAb":"2027-01-18","teilnahmeOffen":true,
         "einheit":{"id":"e1","name":"JF Beispielstadt","typ":"jf"},
         "teilnehmende":[{"id":"t1","vorname":"Max","status":null,"abzeichen":null}],"eigeneAnmeldung":"offen",
         "thema":"Knoten","info":null,"aufgebot":"Bis 17 Uhr",
         "kontakt":{"id":"k1","name":"Hans Beispiel","rolle":"kommandant","bildUrl":null,"abzeichen":null,"telefon":"+41 79 000 00 00"}}
        """)
        #expect(timed.start != nil && timed.end != nil && timed.dayFrom == nil)
        #expect(timed.registrationFrom.description == "2027-01-18" && timed.participants.first?.status == nil)
        #expect(timed.contact?.phone == "+41 79 000 00 00" && timed.ownRegistration == "offen")

        let allDay: ProgramList = try decode("""
        {"programme":[{"id":"p2","titel":"Lager","status":"abgesagt","ganztaegig":true,"beginn":null,"ende":null,"tagVon":"2027-07-05",
         "tagBis":"2027-07-09","art":null,"anmeldbar":false,"anmeldungAb":"2027-05-24","teilnahmeOffen":false,
         "einheit":{"id":"e1","name":"JF Beispielstadt","typ":"kf"},"teilnehmende":[]}]}
        """)
        let lager = try #require(allDay.programs.first)
        #expect(lager.dayTo?.description == "2027-07-09" && lager.ownRegistration == nil && lager.contact == nil)
    }

    @Test func participations() throws {
        let value: Participations = try decode("""
        {"zahlen":{"teilnehmende":{"ja":1,"nein":0,"offen":1},"leitende":{"ja":1,"nein":0,"offen":0}},
         "teilnehmende":[{"id":"t1","vorname":"Max","nachname":"Beispiel","status":"ja","abzeichen":{"kuerzel":"R1","sterne":2,"bildUrl":null}}],
         "leitende":[{"id":"l1","name":"Hans Beispiel","bildUrl":null,"rolle":"kommandant","status":"ja","abzeichen":null}]}
        """)
        #expect(value.counts.participants.open == 1 && value.participants.first?.badge?.stars == 2)
        #expect(value.leaders.first?.role == "kommandant")
    }

    @Test func consentPrivacyAndContact() throws {
        let consent: Consent = try decode(#"{"version":2,"text":"Einverstanden?","gueltig":false}"#)
        #expect(consent.version == 2 && !consent.isValid)
        let privacy: Privacy = try decode(#"{"version":2,"abschnitte":[{"titel":"Zweck","text":"Text\n\n– Punkt"}]}"#)
        #expect(privacy.sections.first?.title == "Zweck")
        let none: UnitContact = try decode(#"{"kontakt":null}"#)
        #expect(none.contact == nil)
    }

    @Test func profileSettingsEncodesOnlySetFields() throws {
        func json(_ settings: ProfileSettings) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return String(bytes: try encoder.encode(settings), encoding: .utf8) ?? ""
        }
        #expect(try json(ProfileSettings(pushPrograms: false)) == #"{"pushProgramme":false}"#)
        #expect(try json(ProfileSettings(phone: .some("+41 79 000 00 00"))) == #"{"telefon":"+41 79 000 00 00"}"#)
        #expect(try json(ProfileSettings(phone: .some(nil))) == #"{"telefon":null}"#)
    }
}

// MARK: Infokanal (Issue #68)

/// Fake des Netzes für den Infokanal; Namen und Texte sind erfunden.
private final class FakeInfoService: InfoChannelService, @unchecked Sendable {
    struct State {
        var pages: [InfoMessagePage] = []
        var posted: [String] = []
        var edited: [String] = []
        var deleted: [String] = []
        var readCalls = 0
        var failWrites = false
        var failLoad = false
    }

    let state = OSAllocatedUnfairLock(initialState: State())
    let channels: [InfoChannel]

    init(channels: [InfoChannel] = []) { self.channels = channels }

    func infoChannels() async -> ApiResult<InfoChannelList> { .ok(InfoChannelList(channels: channels)) }

    func infoMessages(unitId: String, before: String?, limit: Int) async -> ApiResult<InfoMessagePage> {
        state.withLock { current in
            if current.failLoad { return .failure(.network) }
            let index = before == nil ? 0 : 1
            return current.pages.indices.contains(index) ? .ok(current.pages[index]) : .failure(.notFound)
        }
    }

    func postInfoMessage(unitId: String, text: String) async -> ApiResult<InfoMessage> {
        state.withLock { current in
            if current.failWrites { return .failure(.forbidden) }
            current.posted.append(text)
            return .ok(InfoMessage.sample(id: "neu", text: text, own: true))
        }
    }

    func editInfoMessage(unitId: String, messageId: String, text: String) async -> ApiResult<InfoMessage> {
        state.withLock { current in
            if current.failWrites { return .failure(.forbidden) }
            current.edited.append(text)
            return .ok(InfoMessage.sample(id: messageId, text: text, own: true, edited: true))
        }
    }

    func deleteInfoMessage(unitId: String, messageId: String) async -> ApiResult<Void> {
        state.withLock { current in
            if current.failWrites { return .failure(.forbidden) }
            current.deleted.append(messageId)
            return .ok(())
        }
    }

    func markInfoRead(unitId: String) async -> ApiResult<Void> {
        state.withLock { $0.readCalls += 1 }
        return .ok(())
    }
}

private extension InfoMessage {
    nonisolated static func sample(id: String, text: String?, own: Bool = false, edited: Bool = false, canEdit: Bool = true, canDelete: Bool = true) -> InfoMessage {
        InfoMessage(
            id: id, text: text, isDeleted: false, isEdited: edited, createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            author: InfoAuthor(name: "Petra Beispiel", role: "kommando", imagePath: nil), isOwn: own, canEdit: canEdit, canDelete: canDelete
        )
    }
}

private extension InfoChannel {
    nonisolated static func sample(canWrite: Bool, unread: Int = 0) -> InfoChannel {
        InfoChannel(unit: ProgramUnit(id: "0f8fad5b-d9cb-469f-a165-70867728950e", name: "Jugendfeuerwehr Beispielstadt", type: "jf"),
                    name: "Infokanal Jugendfeuerwehr Beispielstadt", canWrite: canWrite, unread: unread, lastMessageAt: nil)
    }
}

@MainActor
struct InfoChannelTests {
    @Test func decodesChannelsAndMessages() throws {
        let list = try JSONDecoder.api.decode(InfoChannelList.self, from: Data("""
        {"infokanaele":[{"einheit":{"id":"e1","name":"Jugendfeuerwehr Beispielstadt","typ":"jf"},"name":"Infokanal Jugendfeuerwehr Beispielstadt",
         "darfSchreiben":true,"ungelesen":3,"letzteMitteilungAm":"2026-11-13T12:00:00.000Z"}]}
        """.utf8))
        #expect(list.channels.first?.unread == 3 && list.channels.first?.canWrite == true && list.channels.first?.id == "e1")
        let page = try JSONDecoder.api.decode(InfoMessagePage.self, from: Data("""
        {"darfSchreiben":false,"naechste":"m0","mitteilungen":[
         {"id":"m2","text":"Hallo","geloescht":false,"bearbeitet":true,"erstelltAm":"2026-11-13T12:00:00.000Z",
          "autor":{"name":"Petra Beispiel","rolle":"kommando","bildUrl":null},"eigene":false,"darfBearbeiten":false,"darfLoeschen":false},
         {"id":"m1","text":null,"geloescht":true,"bearbeitet":false,"erstelltAm":"2026-11-13T11:00:00.000Z","autor":null,
          "eigene":false,"darfBearbeiten":false,"darfLoeschen":false}]}
        """.utf8))
        #expect(page.next == "m0" && !page.canWrite && page.messages[0].isEdited && page.messages[1].isDeleted && page.messages[1].author == nil)
    }

    @Test func unreadBadgeIsTheSumOverAllUnits() async {
        let service = FakeInfoService(channels: [.sample(canWrite: true, unread: 2), InfoChannel(
            unit: ProgramUnit(id: "e2", name: "Kinderfeuerwehr Beispielstadt", type: "kf"), name: "Infokanal Kinderfeuerwehr Beispielstadt",
            canWrite: false, unread: 1, lastMessageAt: nil)])
        let model = InfoChannelsModel(service: service)
        await model.load()
        #expect(model.unreadTotal == 3)
        model.markedRead(unitId: "e2")
        #expect(model.unreadTotal == 2)
    }

    @Test func historyShowsNewestLastAndMarksItRead() async {
        let service = FakeInfoService()
        service.state.withLock {
            $0.pages = [InfoMessagePage(canWrite: false, messages: [.sample(id: "m2", text: "neu"), .sample(id: "m1", text: "alt")], next: "m1")]
        }
        var read = 0
        let model = InfoConversationModel(channel: .sample(canWrite: false), service: service, onRead: { read += 1 })
        await model.load()
        #expect(model.messages.map(\.id) == ["m1", "m2"] && !model.canWrite && model.next == "m1")
        #expect(service.state.withLock { $0.readCalls } == 1 && read == 1)
        await model.markRead() // dieselbe neueste Mitteilung: nicht noch einmal
        #expect(service.state.withLock { $0.readCalls } == 1)
    }

    @Test func olderPagesComeFirst() async {
        let service = FakeInfoService()
        service.state.withLock {
            $0.pages = [InfoMessagePage(canWrite: true, messages: [.sample(id: "m2", text: "b")], next: "m2"),
                        InfoMessagePage(canWrite: true, messages: [.sample(id: "m1", text: "a")], next: nil)]
        }
        let model = InfoConversationModel(channel: .sample(canWrite: true), service: service)
        await model.load()
        await model.loadOlder()
        #expect(model.messages.map(\.id) == ["m1", "m2"] && model.next == nil)
    }

    @Test func sendingNeedsWritePermissionAndATextOfValidLength() async {
        let reader = InfoConversationModel(channel: .sample(canWrite: false), service: FakeInfoService())
        #expect(await reader.send("Hallo") == false)

        let service = FakeInfoService()
        service.state.withLock { $0.pages = [InfoMessagePage(canWrite: true, messages: [], next: nil)] }
        let writer = InfoConversationModel(channel: .sample(canWrite: true), service: service)
        await writer.load()
        #expect(await writer.send("   ") == false)
        #expect(await writer.send(String(repeating: "a", count: InfoConversationModel.maxLength + 1)) == false)
        #expect(await writer.send("  Treffpunkt ist um 13:00.  ") == true)
        #expect(service.state.withLock { $0.posted } == ["Treffpunkt ist um 13:00."] && writer.messages.last?.id == "neu" && writer.sentCount == 1)
    }

    @Test func failedSendKeepsTheErrorAndCountsIt() async {
        let service = FakeInfoService()
        service.state.withLock { $0.pages = [InfoMessagePage(canWrite: true, messages: [], next: nil)]; $0.failWrites = true }
        let model = InfoConversationModel(channel: .sample(canWrite: true), service: service)
        await model.load()
        #expect(await model.send("Hallo") == false)
        #expect(model.composer == .failed(.forbidden) && model.failedCount == 1 && model.messages.isEmpty)
    }

    @Test func editingReplacesTheMessageAndDeletingLeavesAPlaceholder() async {
        let service = FakeInfoService()
        service.state.withLock {
            $0.pages = [InfoMessagePage(canWrite: true, messages: [.sample(id: "m1", text: "alt", own: true)], next: nil)]
        }
        let model = InfoConversationModel(channel: .sample(canWrite: true), service: service)
        await model.load()
        model.startEditing(model.messages[0])
        #expect(model.editing?.id == "m1")
        #expect(await model.saveEdit("neu") == true)
        #expect(model.messages[0].text == "neu" && model.messages[0].isEdited && model.editing == nil)

        await model.delete(model.messages[0])
        #expect(model.messages[0].isDeleted && model.messages[0].text == nil && model.messages[0].author == nil)
        #expect(service.state.withLock { $0.deleted } == ["m1"])
    }

    @Test func menuRightsFollowTheServerFlags() async {
        let service = FakeInfoService()
        service.state.withLock {
            $0.pages = [InfoMessagePage(canWrite: true, messages: [.sample(id: "m1", text: "fremd", canEdit: false, canDelete: false)], next: nil)]
        }
        let model = InfoConversationModel(channel: .sample(canWrite: true), service: service)
        await model.load()
        model.startEditing(model.messages[0])
        await model.delete(model.messages[0])
        #expect(model.editing == nil && service.state.withLock { $0.deleted }.isEmpty)
    }

    @Test func newMarkersFollowTheUnreadCountAndNewArrivals() async {
        let service = FakeInfoService()
        service.state.withLock {
            $0.pages = [InfoMessagePage(canWrite: true, messages: [.sample(id: "m3", text: "eigene", own: true), .sample(id: "m2", text: "b"), .sample(id: "m1", text: "a")], next: nil)]
        }
        let model = InfoConversationModel(channel: .sample(canWrite: true, unread: 1), service: service)
        await model.load()
        #expect(model.newIds == ["m2"]) // eine ungelesene: die neueste von anderen; die eigene zählt nie
        service.state.withLock {
            $0.pages = [InfoMessagePage(canWrite: true, messages: [.sample(id: "m5", text: "neu"), .sample(id: "m4", text: "eigen", own: true),
                                                                    .sample(id: "m3", text: "eigene", own: true), .sample(id: "m2", text: "b"), .sample(id: "m1", text: "a")], next: nil)]
        }
        await model.load()
        #expect(model.newIds == ["m2", "m5"])
    }

    @Test func onlyHttpLinksBecomeTappable() {
        let text = "Infos: https://example.org/lager, Mail: mailto:test@example.org, ftp://example.org/datei"
        let links = InfoText.attributed(text).runs.compactMap(\.link)
        #expect(links == [URL(string: "https://example.org/lager")])
    }

    @Test func pushTargetsForTheInfoChannel() {
        let unit = "0f8fad5b-d9cb-469f-a165-70867728950e"
        #expect(PushTarget.from(type: "infokanal", id: unit) == .infoChannel(unitId: unit))
        #expect(PushTarget.from(type: "infokanal", id: "../ich") == nil)
        // Nr. 29: Push aus dem Backend (`mitteilung`, ohne `id`) öffnet nur die App.
        #expect(PushTarget.from(type: "mitteilung", id: nil) == nil)
        #expect(PushTarget.from(type: "mitteilung", id: unit) == nil)
        #expect(PushTarget.from(userInfo: ["typ": "etwas-neues"]) == nil)
    }

    @Test func routerKeepsInfoChannelAndAppointmentApart() {
        let router = PushRouter()
        let unit = "0f8fad5b-d9cb-469f-a165-70867728950e"
        router.open(.infoChannel(unitId: unit))
        #expect(router.pending == nil && router.consume() == nil)
        #expect(router.consumeInfoChannel() == unit && router.consumeInfoChannel() == nil)
        router.open(.appointment(id: unit))
        #expect(router.pending == .appointment(id: unit) && router.consumeInfoChannel() == nil)
    }
}
