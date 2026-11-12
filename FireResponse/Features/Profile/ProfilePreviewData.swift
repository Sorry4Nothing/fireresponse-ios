#if DEBUG
import Foundation

/// Erfundene Daten für Vorschauen und Tests.
enum ProfilePreviewData {
    static func profile(parent: Bool = true, units: Int = 1) -> Profile {
        let unitJSON = (0..<units).map { index in
            #"{"id":"u\#(index)","name":"Musterstadt \#(index + 1)","typ":"jf","bezirk":"Beispielbezirk","rolle":"leitung"}"#
        }.joined(separator: ",")
        let childJSON = parent ? #"""
        {"id":"p1","vorname":"Mia","nachname":"Muster","einheitId":"u0","einheitName":"JF Beispielstadt","einheitTyp":"jf","art":"eltern","abzeichen":{"kuerzel":"A","sterne":1}},
        {"id":"p2","vorname":"Noah","nachname":"Muster","einheitId":"u0","einheitName":"KF Beispielstadt","einheitTyp":"kf","art":"eltern","abzeichen":{"kuerzel":"B","sterne":2}}
        """# : ""
        let json = #"""
        {"id":"x1","name":"Alex Muster","benutzername":"alex.muster","kantonsadmin":false,"zweiterFaktor":false,
        "einwilligung":true,"mussPasswortAendern":false,"pushProgramme":true,
        "einheiten":[\#(parent ? "" : unitJSON)],"teilnehmende":[\#(childJSON)]}
        """#
        // Die Vorschau-JSON ist fest eingebaut; ein Fehler fiele sofort auf.
        // swiftlint:disable:next force_try
        return try! JSONDecoder.api.decode(Profile.self, from: Data(json.utf8))
    }
}
#endif
