import Foundation
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
