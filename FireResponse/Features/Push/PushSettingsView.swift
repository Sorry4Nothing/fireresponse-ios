import SwiftUI
import UserNotifications

/// Push-Einstellungen, vom Profil aus erreichbar: welche Mitteilungen die Person bekommt. Die Schalter gelten beim Server,
/// nicht auf diesem Gerät; ob das Gerät der App Mitteilungen zeigen lässt, entscheidet das System.
/// Im Design nicht gezeichnet: aus Listenzeile und Schalter laut Umschalter-Vorgabe gebaut.
struct PushSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PushSettingsForm(
            programs: model.profile?.pushPrograms ?? true,
            registrations: model.profile?.pushRegistrations,
            infoChannel: model.profile?.pushInfoChannel ?? true,
            authorization: PushCenter.shared.authorization,
            requestAuthorization: { await PushCenter.shared.requestAuthorization() },
            refreshAuthorization: { await PushCenter.shared.refreshAuthorization() },
            save: { [model] settings in
                let result = await model.api.updateMe(settings)
                // Das Profil im Speicher nachziehen, damit die Seite beim nächsten Öffnen den neuen Stand zeigt.
                if case .ok = result, case .ok(let fresh) = await model.api.me() { model.profile = fresh }
                return result
            }
        )
    }
}

struct PushSettingsForm: View {
    @State private var settings: PushSettingsModel
    let authorization: UNAuthorizationStatus
    let requestAuthorization: () async -> Void
    let refreshAuthorization: () async -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AccessibilityFocusState private var errorFocused: Bool

    init(
        programs: Bool,
        registrations: Bool?,
        infoChannel: Bool = true,
        authorization: UNAuthorizationStatus,
        requestAuthorization: @escaping () async -> Void,
        refreshAuthorization: @escaping () async -> Void,
        save: @escaping (ProfileSettings) async -> ApiResult<Void>
    ) {
        _settings = State(initialValue: PushSettingsModel(programs: programs, registrations: registrations, infoChannel: infoChannel, save: save))
        self.authorization = authorization
        self.requestAuthorization = requestAuthorization
        self.refreshAuthorization = refreshAuthorization
    }

    var body: some View {
        List {
            systemSection
            Section {
                Toggle(isOn: binding(\.programs) { await settings.setPrograms($0) }) {
                    ListRow("Neue Übungen", systemImage: "calendar")
                }
                .tint(.frSwitchOn)
            } footer: {
                Text("Neue Übungen, Erinnerungen, Absagen und Änderungen.")
            }
            .listRowBackground(Color.frSurfaceContainerLow)
            Section {
                Toggle(isOn: binding(\.infoChannel) { await settings.setInfoChannel($0) }) {
                    ListRow("Neue Mitteilungen im Infokanal", systemImage: "megaphone")
                }
                .tint(.frSwitchOn)
            } footer: {
                Text("Wenn Kommando oder Leitung deiner Einheit eine Mitteilung schreibt. Der Text steht nie in der Mitteilung.")
            }
            .listRowBackground(Color.frSurfaceContainerLow)
            if settings.registrations != nil {
                Section {
                    Toggle(isOn: Binding(
                        get: { settings.registrations ?? false },
                        set: { value in Task { await settings.setRegistrations(value) } }
                    )) {
                        ListRow("Neue Anmeldungen", systemImage: "person.2")
                    }
                    .tint(.frSwitchOn)
                } footer: {
                    Text("Wenn sich jemand für eine Übung deiner Einheit an- oder abmeldet.")
                }
                .listRowBackground(Color.frSurfaceContainerLow)
            }
            if settings.saveFailed {
                Section {
                    Notice(.error, title: "Speichern hat nicht geklappt", message: "Prüfe die Verbindung und versuche es noch einmal.")
                        .accessibilityFocused($errorFocused)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {} footer: {
                Text("Mitteilungen enthalten nie Namen von Kindern.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.frSurface)
        .navigationTitle("Benachrichtigungen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAuthorization() }
        // Nach den Einstellungen des Systems kommt die Person zurück: dann gilt der neue Stand.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshAuthorization() } }
        }
        .onChange(of: settings.saveFailed) { _, failed in errorFocused = failed }
    }

    @ViewBuilder private var systemSection: some View {
        switch authorization {
        case .denied:
            Section {
              VStack(spacing: Spacing.s3) {
                Notice(.warning, title: "Mitteilungen sind ausgeschaltet", message: "Schalte sie in den Einstellungen des iPhones ein, sonst kommen keine an.")
                FRButton("Einstellungen öffnen", systemImage: "gearshape", kind: .outline) {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
              }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        case .notDetermined:
            Section {
              VStack(spacing: Spacing.s3) {
                Notice(.info, title: "Mitteilungen sind noch nicht erlaubt", message: "Erlaube sie, damit neue Übungen bei dir ankommen.")
                FRButton("Mitteilungen erlauben", systemImage: "bell", kind: .main) {
                    Task { await requestAuthorization() }
                }
              }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        default:
            EmptyView()
        }
    }

    private func binding(_ keyPath: KeyPath<PushSettingsModel, Bool>, set: @escaping (Bool) async -> Void) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { value in Task { await set(value) } })
    }
}

#if DEBUG
private struct PushSettingsDemo: View {
    let authorization: UNAuthorizationStatus
    let registrations: Bool?

    var body: some View {
        NavigationStack {
            PushSettingsForm(
                programs: true,
                registrations: registrations,
                authorization: authorization,
                requestAuthorization: {},
                refreshAuthorization: {},
                save: { _ in .ok(()) }
            )
        }
    }
}

#Preview("Nacht, AX5, ausgeschaltet") { PushSettingsDemo(authorization: .denied, registrations: false).preferredColorScheme(.dark).dynamicTypeSize(.accessibility5) }
#Preview("Tag, normal, Leitung") { PushSettingsDemo(authorization: .authorized, registrations: true).preferredColorScheme(.light) }
#Preview("Nacht, noch nicht gefragt") { PushSettingsDemo(authorization: .notDetermined, registrations: nil).preferredColorScheme(.dark) }
#endif
