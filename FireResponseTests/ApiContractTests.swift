import Foundation
import Testing
@testable import FireResponse

/// Jeder Aufruf der App steht im Vertrag des Backends (`api-vertrag/openapi.yaml`). Geprüft werden Methode und Pfad; die Felder
/// prüfen `ModelsTests` mit Beispiel-JSON. Wie Androids `ApiContractTest`: Der Test liest zuerst, ob er überhaupt etwas findet.
struct ApiContractTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static let endpointFile = "Endpoint.swift"

    /// `{id}`, `{einheitId}` und `$id` zählen gleich: Es kommt auf den Pfad an, nicht auf den Namen des Platzhalters.
    private func normalize(_ path: String) -> String {
        path.split(separator: "?").first.map(String.init)?
            .replacingOccurrences(of: "\\{[^}]*\\}", with: "{}", options: .regularExpression) ?? path
    }

    private func contract() throws -> Set<String> {
        let text = try String(contentsOf: Self.root.appending(path: "api-vertrag/openapi.yaml"), encoding: .utf8)
        var operations: Set<String> = []
        var path: String?
        var inPaths = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line == "paths:" { inPaths = true; continue }
            if inPaths, line == "components:" { break }
            guard inPaths else { continue }
            if let match = line.wholeMatch(of: /\x20\x20(\/\S*):\s*/) { path = String(match.1) }
            if let match = line.wholeMatch(of: /\x20{4}(get|post|put|patch|delete):\s*/), let path {
                operations.insert("\(match.1.uppercased()) \(normalize(path))")
            }
        }
        return operations
    }

    private func swiftFiles() -> [URL] {
        let enumerator = FileManager.default.enumerator(at: Self.root.appending(path: "FireResponse"), includingPropertiesForKeys: nil)
        return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
    }

    @Test func theTestFindsWhatItChecks() throws {
        // Ein Test, der nichts findet, besteht immer: Darum zuerst prüfen, dass er etwas findet.
        #expect(try contract().count > 40)
        #expect(try contract().contains("PUT /api/v1/programme/{}/teilnahmen/{}"))
        #expect(!swiftFiles().isEmpty)
        #expect(Endpoint.allCases.count > 15)
    }

    @Test func everyEndpointIsInTheContract() throws {
        let contract = try contract()
        let missing = Endpoint.allCases
            .map { "\($0.method.rawValue) \(normalize($0.template))" }
            .filter { !contract.contains($0) }
        #expect(missing.isEmpty, "Nicht im Vertrag: \(missing)")
    }

    @Test func noPathOutsideTheEndpointList() throws {
        // Jedes Zeichenketten-Literal mit «/api/» steht in Endpoint.swift und dort in der Liste; sonst ginge ein Aufruf am Test vorbei.
        let literal = /"([^"\n]*\/api\/[^"\n]*)"/
        var found: Set<String> = []
        for file in swiftFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: literal) {
                // Ein Präfix wie «/api/v1/» (endet auf «/») ist kein Pfad.
                if file.lastPathComponent == Self.endpointFile, match.1.hasSuffix("/") { continue }
                #expect(file.lastPathComponent == Self.endpointFile, "Pfad ausserhalb von Endpoint.swift: \(match.1) in \(file.lastPathComponent)")
                found.insert(normalize(String(match.1)))
            }
        }
        #expect(found == Set(Endpoint.allCases.map { normalize($0.template) }))
    }

    @Test func onlyTheClientTalksToTheNetwork() throws {
        for file in swiftFiles() where file.lastPathComponent != "ApiClient.swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("URLSession.shared") && !text.contains("URLSession(") && !text.contains("URLRequest("),
                    "Netzzugriff ausserhalb von ApiClient.swift: \(file.lastPathComponent)")
        }
    }

    @Test func endpointsCoverEveryOperationOfTheAppContract() throws {
        // Was Android nutzt und der Vertrag der App kennt.
        let expected: Set<String> = [
            "POST /api/auth/sign-in/username", "POST /api/auth/sign-out", "GET /api/auth/get-session", "POST /api/auth/change-password",
            "GET /api/v1/ich", "PATCH /api/v1/ich", "PUT /api/v1/ich/bild", "DELETE /api/v1/ich/bild",
            "GET /api/v1/einwilligung", "PUT /api/v1/einwilligung", "GET /api/v1/datenschutz", "GET /api/v1/programme",
            "GET /api/v1/programme/{}", "GET /api/v1/programme/{}/teilnahmen", "PUT /api/v1/programme/{}/teilnahmen/{}",
            "PUT /api/v1/programme/{}/leitung", "GET /api/v1/einheiten/{}/kontakt", "GET /api/v1/raenge/{}/abzeichen",
            "GET /api/v1/personen/{}/bild", "GET /api/v1/einheiten/{}/logo", "PUT /api/v1/push-token",
            "GET /api/v1/wartung", "GET /api/v1/infokanaele", "GET /api/v1/infokanaele/{}/mitteilungen",
            "POST /api/v1/infokanaele/{}/mitteilungen", "PUT /api/v1/infokanaele/{}/mitteilungen/{}",
            "DELETE /api/v1/infokanaele/{}/mitteilungen/{}", "PUT /api/v1/infokanaele/{}/gelesen",
        ]
        let actual = Set(Endpoint.allCases.map { "\($0.method.rawValue) \(normalize($0.template))" })
        #expect(actual == expected)
    }
}
