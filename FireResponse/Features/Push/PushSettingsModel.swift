import Observation

/// Die Push-Schalter der Person. Ein Schalter springt sofort um; schlägt das Speichern fehl, springt er zurück und
/// die Person bekommt eine Meldung. `registrations` ist `nil` bei Personen ohne Rolle in einer Einheit (kein Schalter).
@MainActor @Observable
final class PushSettingsModel {
    private(set) var programs: Bool
    private(set) var registrations: Bool?
    private(set) var isSaving = false
    private(set) var saveFailed = false

    private let save: (ProfileSettings) async -> ApiResult<Void>

    init(programs: Bool, registrations: Bool?, save: @escaping (ProfileSettings) async -> ApiResult<Void>) {
        self.programs = programs
        self.registrations = registrations
        self.save = save
    }

    func setPrograms(_ on: Bool) async {
        let old = programs
        await apply(ProfileSettings(pushPrograms: on), set: { self.programs = on }, undo: { self.programs = old })
    }

    func setRegistrations(_ on: Bool) async {
        let old = registrations
        await apply(ProfileSettings(pushRegistrations: on), set: { self.registrations = on }, undo: { self.registrations = old })
    }

    private func apply(_ settings: ProfileSettings, set: () -> Void, undo: () -> Void) async {
        guard !isSaving else { return }
        isSaving = true
        saveFailed = false
        set()
        if case .ok = await save(settings) {} else {
            undo()
            saveFailed = true
        }
        isSaving = false
    }
}
