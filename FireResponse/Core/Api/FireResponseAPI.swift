import Foundation

/// Typisierte Aufrufe der Endpunkte, die die App nutzt. Dünn: keine Logik, nur Pfad, Body und Typ.
/// Die Pfade stehen in `Endpoint`; Fehler und Header regelt `ApiClient`.
nonisolated struct FireResponseAPI: Sendable {
    let client: ApiClient

    /// Höchstgrösse eines Profilbilds, Abzeichens oder Logos beim Laden (JPEG 256 × 256 hat rund 20 bis 80 KB).
    static let maxImageBytes = 512 * 1024

    // MARK: Anmeldung

    /// Bei `needsSecondFactor` gibt es noch keine Sitzung. Der zweite Faktor gehört nicht zu V1 (Android kennt ihn nur für die Verwaltung).
    func signIn(username: String, password: String) async -> ApiResult<SignInResponse> {
        await client.send(.signIn, body: .json(SignInRequest(username: username, password: password)))
    }

    /// Verwirft die Sitzung lokal immer, auch wenn der Server nicht antwortet (er beendet sie dann mit ihrem Ablauf).
    func signOut() async -> ApiResult<Void> {
        let result = await client.sendDiscardingBody(.signOut)
        await client.forgetSession()
        return result
    }

    /// `nil` bei `.ok`: keine gültige Sitzung. Verlängert die Sitzung, wenn es fällig ist (neues Cookie, das der Client übernimmt).
    func session() async -> ApiResult<AuthSession?> {
        await client.send(.session)
    }

    /// Beendet alle anderen Sitzungen; das neue Cookie dieses Geräts übernimmt der Client. Fehlercodes bei `.failure`: `INVALID_PASSWORD`,
    /// `PASSWORT_UNVERAENDERT`, `PASSWORD_COMPROMISED`, `PASSWORD_TOO_SHORT`, `PASSWORD_TOO_LONG`.
    func changePassword(current: String, new: String) async -> ApiResult<Void> {
        await client.sendDiscardingBody(.changePassword, body: .json(ChangePasswordRequest(currentPassword: current, newPassword: new)))
    }

    // MARK: Profil

    func me() async -> ApiResult<Profile> {
        await client.send(.me)
    }

    func updateMe(_ settings: ProfileSettings) async -> ApiResult<Void> {
        await client.sendDiscardingBody(.updateMe, body: .json(settings))
    }

    /// JPEG, PNG oder WebP, höchstens 5 MiB; der Server erkennt den Typ an den Bytes.
    func setMyImage(_ image: Data, contentType: String = "image/jpeg") async -> ApiResult<Void> {
        await client.sendDiscardingBody(.putMyImage, body: .bytes(image, contentType: contentType))
    }

    func deleteMyImage() async -> ApiResult<Void> {
        await client.sendDiscardingBody(.deleteMyImage)
    }

    func consent() async -> ApiResult<Consent> {
        await client.send(.consent)
    }

    /// Die Fassung setzt der Server.
    func giveConsent() async -> ApiResult<Void> {
        await client.sendDiscardingBody(.giveConsent)
    }

    /// Öffentlich, auch vor der Anmeldung.
    func privacy() async -> ApiResult<Privacy> {
        await client.send(.privacy)
    }

    // MARK: Programme

    /// Programme, die das Fenster berühren; Schweizer Kalendertage, beidseitig inklusive.
    func programs(from: SwissDay, to: SwissDay) async -> ApiResult<ProgramList> {
        await client.send(.programs, query: [URLQueryItem(name: "von", value: from.description), URLQueryItem(name: "bis", value: to.description)])
    }

    func program(id: String) async -> ApiResult<Program> {
        await client.send(.program, values: [id])
    }

    func participations(programId: String) async -> ApiResult<Participations> {
        await client.send(.participations, values: [programId])
    }

    /// Antwort einer eigenen teilnehmenden Person; 409-Gründe stehen in `ApiError`.
    func setParticipation(programId: String, participantId: String, answer: Answer) async -> ApiResult<Void> {
        await client.sendDiscardingBody(.setParticipation, values: [programId, participantId], body: .json(AnswerRequest(status: answer)))
    }

    /// Eigene Anmeldung als Kommando, Stellvertretung oder Leitung.
    func setLeadership(programId: String, answer: Answer) async -> ApiResult<Void> {
        await client.sendDiscardingBody(.setLeadership, values: [programId], body: .json(AnswerRequest(status: answer)))
    }

    func unitContact(unitId: String) async -> ApiResult<UnitContact> {
        await client.send(.unitContact, values: [unitId])
    }

    // MARK: Bilder (Adresse aus `imagePath` des Servers; andere Pfade lädt der Client nicht)

    func personImage(path: String) async -> ApiResult<Data> {
        await client.perform(.personImage, rawPath: path, maxBytes: Self.maxImageBytes)
    }

    func badgeImage(path: String) async -> ApiResult<Data> {
        await client.perform(.badgeImage, rawPath: path, maxBytes: Self.maxImageBytes)
    }

    // MARK: Push

    /// Der Server verlangt 20 bis 512 Zeichen aus Buchstaben, Ziffern und `_ : . -` und die Plattform `ios`.
    func registerPushToken(_ token: String) async -> ApiResult<Void> {
        await client.sendDiscardingBody(.pushToken, body: .json(PushTokenRequest(token: token, plattform: "ios")))
    }
}
