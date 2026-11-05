#if DEBUG
import Foundation
import os
import SwiftUI

/// Erfundene Daten für Vorschauen; nie echte Namen. Antworten bleiben im Arbeitsspeicher.
final class PreviewExercisesService: ExercisesService, @unchecked Sendable {
    private let answers = OSAllocatedUnfairLock(initialState: [String: String]())
    private let leader: Bool

    init(leader: Bool = false) { self.leader = leader }

    private func iso(days: Int, hour: Int, minute: Int = 0) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = SwissDay.timeZone
        let base = calendar.date(byAdding: .day, value: days, to: .now) ?? .now
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        return ISO8601DateFormatter().string(from: date)
    }

    private func day(_ offset: Int) -> String {
        SwissDay(date: Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now).description
    }

    private func participantsJSON(_ id: String) -> String {
        let anna = answers.withLock { $0["\(id)/anna"] }
        let ben = answers.withLock { $0["\(id)/ben"] } ?? "ja"
        func status(_ value: String?) -> String { value.map { "\"\($0)\"" } ?? "null" }
        return #"[{"id":"anna","vorname":"Anna","status":\#(status(anna)),"abzeichen":null},{"id":"ben","vorname":"Ben","status":\#(status(ben)),"abzeichen":null}]"#
    }

    private func programJSON(_ id: String) -> String {
        let own = leader ? #""eigeneAnmeldung":"\#(answers.withLock { $0["\(id)/leitung"] } ?? "offen")","# : ""
        switch id {
        case "p1":
            return #"""
            {"id":"p1","titel":"Schläuche kuppeln","status":"aktiv","ganztaegig":false,"beginn":"\#(iso(days: 3, hour: 14))","ende":"\#(iso(days: 3, hour: 17))",
             "art":"Übung","anmeldbar":true,"anmeldungAb":"\#(day(-1))","teilnahmeOffen":true,"einheit":{"id":"e1","name":"JF Beispielstadt","typ":"jf"},
             \#(own)"teilnehmende":\#(participantsJSON(id)),"thema":"Schlauchmaterial und Kupplungen","info":"Bitte pünktlich im Magazin sein.",
             "aufgebot":"Arbeitskleidung, Trinkflasche, feste Schuhe",
             "kontakt":{"id":"k1","name":"Erika Muster","rolle":"kommandant","bildUrl":null,"abzeichen":{"kuerzel":"Oblt","sterne":2,"bildUrl":null},"telefon":"+41 79 000 00 00"}}
            """#
        case "p2":
            return #"""
            {"id":"p2","titel":"Funk und Theorie","status":"aktiv","ganztaegig":false,"beginn":"\#(iso(days: 3, hour: 18))","ende":"\#(iso(days: 3, hour: 19, minute: 30))",
             "art":"Übung","anmeldbar":true,"anmeldungAb":"\#(day(-1))","teilnahmeOffen":true,"einheit":{"id":"e1","name":"JF Beispielstadt","typ":"jf"},
             \#(own)"teilnehmende":\#(participantsJSON(id))}
            """#
        case "p3":
            return #"""
            {"id":"p3","titel":"Übungswochenende","status":"aktiv","ganztaegig":true,"tagVon":"\#(day(70))","tagBis":"\#(day(71))",
             "art":"Übung","anmeldbar":true,"anmeldungAb":"\#(day(28))","teilnahmeOffen":false,"einheit":{"id":"e1","name":"JF Beispielstadt","typ":"jf"},
             \#(own)"teilnehmende":\#(participantsJSON(id))}
            """#
        default:
            return #"""
            {"id":"p4","titel":"Besuch Nachbarfeuerwehr","status":"abgesagt","ganztaegig":false,"beginn":"\#(iso(days: 10, hour: 9))","ende":"\#(iso(days: 10, hour: 12))",
             "art":"Übung","anmeldbar":true,"anmeldungAb":"\#(day(-1))","teilnahmeOffen":false,"einheit":{"id":"e1","name":"JF Beispielstadt","typ":"jf"},
             "teilnehmende":[]}
            """#
        }
    }

    private func decode<T: Decodable>(_ json: String) -> T? { try? JSONDecoder.api.decode(T.self, from: Data(json.utf8)) }

    func programs(from: SwissDay, to: SwissDay) async -> ApiResult<ProgramList> {
        let list: ProgramList? = decode(#"{"programme":[\#(["p1", "p2", "p4", "p3"].map(programJSON).joined(separator: ","))]}"#)
        return list.map { .ok($0) } ?? .failure(.unknown)
    }

    func program(id: String) async -> ApiResult<Program> {
        let program: Program? = decode(programJSON(id))
        return program.map { .ok($0) } ?? .failure(.notFound)
    }

    func participations(programId: String) async -> ApiResult<Participations> {
        let value: Participations? = decode("""
        {"zahlen":{"teilnehmende":{"ja":2,"nein":1,"offen":2},"leitende":{"ja":1,"nein":0,"offen":1}},
         "teilnehmende":[{"id":"t1","vorname":"Ben","nachname":"Beispiel","status":"ja","abzeichen":null},
                         {"id":"t2","vorname":"Anna","nachname":"Muster","status":"offen","abzeichen":null},
                         {"id":"t3","vorname":"Cleo","nachname":"Probe","status":"nein","abzeichen":null},
                         {"id":"t4","vorname":"Dario","nachname":"Test","status":"ja","abzeichen":null},
                         {"id":"t5","vorname":"Eva","nachname":"Beispiel","status":"offen","abzeichen":null}],
         "leitende":[{"id":"l1","name":"Erika Muster","rolle":"kommandant","status":"ja","bildUrl":null,"abzeichen":{"kuerzel":"Oblt","sterne":2,"bildUrl":null}},
                     {"id":"l2","name":"Hans Probe","rolle":"leitung","status":"offen","bildUrl":null,"abzeichen":null}]}
        """)
        return value.map { .ok($0) } ?? .failure(.unknown)
    }

    func setParticipation(programId: String, participantId: String, answer: Answer) async -> ApiResult<Void> {
        try? await Task.sleep(for: .milliseconds(400))
        answers.withLock { $0["\(programId)/\(participantId)"] = answer.rawValue }
        return .ok(())
    }

    func setLeadership(programId: String, answer: Answer) async -> ApiResult<Void> {
        try? await Task.sleep(for: .milliseconds(400))
        answers.withLock { $0["\(programId)/leitung"] = answer.rawValue }
        return .ok(())
    }

    func personImage(path: String) async -> ApiResult<Data> { .failure(.notFound) }
    func badgeImage(path: String) async -> ApiResult<Data> { .failure(.notFound) }

    static var profile: Profile? {
        try? JSONDecoder.api.decode(Profile.self, from: Data("""
        {"id":"u1","name":"Erika Muster","benutzername":"erika.muster","kantonsadmin":false,"zweiterFaktor":false,"einwilligung":true,
         "mussPasswortAendern":false,"telefon":null,"bildUrl":null,"pushProgramme":true,
         "einheiten":[{"id":"e1","name":"JF Beispielstadt","typ":"jf","bezirk":"Bezirk Beispiel","rolle":"leitung","abzeichen":null}],
         "teilnehmende":[{"id":"anna","vorname":"Anna","nachname":"Muster","einheitId":"e1","art":"eltern","abzeichen":null},
                         {"id":"ben","vorname":"Ben","nachname":"Muster","einheitId":"e1","art":"eltern","abzeichen":null}]}
        """.utf8))
    }
}

#Preview("Liste Nacht, normal") { ExercisesStack(service: PreviewExercisesService(), profile: PreviewExercisesService.profile).preferredColorScheme(.dark) }
#Preview("Liste Tag, AX3") {
    ExercisesStack(service: PreviewExercisesService(), profile: PreviewExercisesService.profile).dynamicTypeSize(.accessibility3)
}
#endif
