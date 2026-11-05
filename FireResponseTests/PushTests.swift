import Foundation
import Testing
@testable import FireResponse

private let uuid = "123e4567-e89b-12d3-a456-426614174000"
private let tokenA = "cX1y2Z3a4B5c6D7e8F9g:APA91bAAAAAAAAAAAAAAAAAAAAAAAA"
private let tokenB = "dX1y2Z3a4B5c6D7e8F9g:APA91bBBBBBBBBBBBBBBBBBBBBBBBB"

struct PushTargetTests {
    @Test func parsesProgramTarget() {
        #expect(PushTarget.from(userInfo: ["typ": "programm", "id": uuid, "aps": [:]]) == .appointment(id: uuid))
    }

    @Test func rejectsUnknownTypeAndBadIds() {
        #expect(PushTarget.from(type: "chat", id: uuid) == nil)
        #expect(PushTarget.from(type: nil, id: uuid) == nil)
        #expect(PushTarget.from(type: "programm", id: nil) == nil)
        #expect(PushTarget.from(type: "programm", id: "../ich") == nil)
        #expect(PushTarget.from(type: "programm", id: String(uuid.dropLast()) + "g") == nil)
        #expect(PushTarget.from(userInfo: ["typ": 1, "id": 2]) == nil)
    }

    @MainActor @Test func routerKeepsTargetUntilConsumed() {
        let router = PushRouter()
        router.open(.appointment(id: uuid))
        #expect(router.consume() == .appointment(id: uuid))
        #expect(router.consume() == nil)
    }
}

@MainActor
final class RegisterCalls {
    var tokens: [String] = []
    var result: ApiResult<Void> = .ok(())
}

@MainActor
struct PushTokenRegistrarTests {
    let calls = RegisterCalls()

    func makeRegistrar() -> PushTokenRegistrar {
        PushTokenRegistrar { [calls] token in
            calls.tokens.append(token)
            return calls.result
        }
    }

    @Test func waitsForLoginThenRegistersOnce() async {
        let registrar = makeRegistrar()
        await registrar.setToken(tokenA)
        #expect(calls.tokens.isEmpty)
        await registrar.setSignedIn(true)
        await registrar.setSignedIn(true)
        await registrar.setToken(tokenA)
        #expect(calls.tokens == [tokenA])
    }

    @Test func registersChangedTokenAndNewLogin() async {
        let registrar = makeRegistrar()
        await registrar.setSignedIn(true)
        await registrar.setToken(tokenA)
        await registrar.setToken(tokenB)
        await registrar.setSignedIn(false)
        await registrar.setSignedIn(true)
        #expect(calls.tokens == [tokenA, tokenB, tokenB])
    }

    @Test func retriesAfterFailureAndRejectsInvalidTokens() async {
        let registrar = makeRegistrar()
        await registrar.setSignedIn(true)
        await registrar.setToken("zu kurz")
        await registrar.setToken("ExponentPushToken[abcdefghijklmnopqrstuvwxyz]")
        #expect(calls.tokens.isEmpty)
        calls.result = .failure(.network)
        await registrar.setToken(tokenA)
        calls.result = .ok(())
        await registrar.setToken(tokenA)
        #expect(calls.tokens == [tokenA, tokenA])
    }
}

@MainActor
struct PushSettingsModelTests {
    @Test func switchRollsBackOnFailure() async {
        var sent: [ProfileSettings] = []
        let model = PushSettingsModel(programs: true, registrations: false) { settings in
            sent.append(settings)
            return .failure(.network)
        }
        await model.setPrograms(false)
        #expect(model.programs && model.saveFailed && !model.isSaving)
        await model.setRegistrations(true)
        #expect(model.registrations == false && model.saveFailed)
        #expect(sent.count == 2 && sent[0].pushPrograms == false && sent[0].pushRegistrations == nil)
    }

    @Test func switchKeepsValueOnSuccessAndClearsError() async {
        var succeed = false
        let model = PushSettingsModel(programs: true, registrations: nil) { _ in succeed ? .ok(()) : .failure(.unknown) }
        await model.setPrograms(false)
        #expect(model.saveFailed)
        succeed = true
        await model.setPrograms(false)
        #expect(!model.programs && !model.saveFailed)
        #expect(model.registrations == nil)
    }
}
