import Foundation
import LocalAuthentication
import SwiftUI
import Testing
@testable import FireResponse

nonisolated final class FakeBiometrics: BiometricAuthenticating, @unchecked Sendable {
    var outcome: BiometricOutcome = .success
    var type: LABiometryType = .faceID
    var state: Data? = Data([1])
    private(set) var prompts = 0

    var biometryType: LABiometryType { type }
    var domainState: Data? { state }
    func authenticate(reason: String) async -> BiometricOutcome {
        prompts += 1
        return outcome
    }
}

nonisolated final class MemoryLockStore: LockStore, @unchecked Sendable {
    var baseline: Data?
    init(_ baseline: Data? = nil) { self.baseline = baseline }
    func read() -> Data? { baseline }
    func write(_ baseline: Data) { self.baseline = baseline }
    func clear() { baseline = nil }
}

@MainActor
final class FakeClock {
    var instant = ContinuousClock.now
    func advance(_ seconds: Int) { instant += .seconds(seconds) }
}

@MainActor
struct AppLockTests {
    let biometrics = FakeBiometrics()
    let clock = FakeClock()

    /// Sperre an, gleich entsperrt.
    func makeLock(enabled: Bool = true) async -> (AppLockController, MemoryLockStore) {
        let store = MemoryLockStore(enabled ? Data([1, 1]) : nil)
        let clock = clock
        let lock = AppLockController(authenticator: biometrics, store: store, now: { clock.instant })
        await lock.unlock()
        return (lock, store)
    }

    @Test func startsLockedWhenEnabled() {
        let lock = AppLockController(authenticator: biometrics, store: MemoryLockStore(Data([1, 1])))
        #expect(lock.status == .locked)
        #expect(lock.promptPending)
    }

    @Test func neverLocksWhenDisabled() async {
        let (lock, _) = await makeLock(enabled: false)
        #expect(lock.status == .unlocked)
        lock.scenePhaseChanged(.background)
        clock.advance(3600)
        lock.scenePhaseChanged(.active)
        lock.lock()
        #expect(lock.status == .unlocked)
        #expect(biometrics.prompts == 0)
    }

    @Test func locksAfterThirtySecondsInBackground() async {
        let (lock, _) = await makeLock()
        #expect(lock.status == .unlocked)
        lock.scenePhaseChanged(.background)
        clock.advance(29)
        lock.scenePhaseChanged(.active)
        #expect(lock.status == .unlocked)

        lock.scenePhaseChanged(.background)
        clock.advance(30)
        lock.scenePhaseChanged(.active)
        #expect(lock.status == .locked)
    }

    @Test func inactiveAloneDoesNotStartTheTimer() async {
        let (lock, _) = await makeLock()
        lock.scenePhaseChanged(.inactive)
        clock.advance(120)
        lock.scenePhaseChanged(.active)
        #expect(lock.status == .unlocked)
    }

    @Test func failureAndCancelKeepItLocked() async {
        let (lock, _) = await makeLock()
        lock.lock()
        biometrics.outcome = .failed
        await lock.unlock()
        #expect(lock.status == .locked)
        #expect(lock.lastAttemptFailed)

        biometrics.outcome = .cancelled
        await lock.unlock()
        #expect(lock.status == .locked)
        #expect(!lock.lastAttemptFailed)

        biometrics.outcome = .unavailable
        await lock.unlock()
        #expect(lock.status == .locked)

        biometrics.outcome = .success
        await lock.unlock()
        #expect(lock.status == .unlocked)
    }

    @Test func changedBiometryStaysClosedWithoutPrompting() async {
        let (lock, store) = await makeLock()
        lock.lock()
        let prompts = biometrics.prompts
        biometrics.state = Data([9])
        await lock.unlock()
        #expect(lock.status == .biometryChanged)
        #expect(biometrics.prompts == prompts)
        await lock.unlock()
        #expect(lock.status == .biometryChanged)
        #expect(store.baseline != nil) // erst das Abmelden löscht die Einstellung
    }

    @Test func enableNeedsBiometryAndSuccess() async {
        let (lock, store) = await makeLock(enabled: false)
        biometrics.type = .none
        #expect(await lock.enable() == false)
        biometrics.type = .faceID
        biometrics.outcome = .failed
        #expect(await lock.enable() == false)
        #expect(store.baseline == nil)
        biometrics.outcome = .success
        #expect(await lock.enable())
        #expect(store.baseline == Data([1, 1]))
        #expect(lock.isEnabled)
    }

    @Test func disableClearsSettingAndUnlocks() async {
        let (lock, store) = await makeLock()
        lock.lock()
        lock.disable()
        #expect(store.baseline == nil)
        #expect(!lock.isEnabled)
        #expect(lock.status == .unlocked)
    }
}
