import LocalAuthentication
import PhotosUI
import SwiftUI

/// Profil: Kopf mit Profilbild, Kinder, App (Benachrichtigungen, Entsperren, Datenschutz), Konto (Einheit, Abmelden).
/// Selbst ändern lassen sich nur das Profilbild und die Sperre; Namen, Rollen, Kinder und Einheit legt die Verwaltung fest.
struct ProfileRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLockController.self) private var lock
    @State private var loadFailed = false
    @State private var confirmSignOut = false
    @State private var signingOut = false
    @State private var unlockOn = false
    @State private var badges: [String: Data] = [:]
    @AccessibilityFocusState private var signOutFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let profile = model.profile {
                    content(profile)
                } else if loadFailed {
                    StateView(.error, primary: { Task { await load() } })
                } else {
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(Text("Profil wird geladen"))
                }
            }
            .background(Color.frSurface)
            .navigationTitle("Profil")
        }
        .task { if model.profile == nil { await load() } }
    }

    private func content(_ profile: Profile) -> some View {
        List {
            Section { ProfileHeader(profile: profile) }
                .listRowBackground(Color.clear)
            if !profile.participants.isEmpty {
                Section("Kinder") {
                    ForEach(profile.participants) { child in
                        ChildRow(child: child, badge: child.badge?.imagePath.flatMap { badges[$0] })
                    }
                }
                .listRowBackground(Color.frSurfaceContainerLow)
            }
            Section {
                NavigationLink { PushSettingsView() } label: { ListRow("Benachrichtigungen", systemImage: "bell") }
                Toggle(isOn: $unlockOn) { ListRow(unlockTitle, systemImage: unlockSymbol) }
                    .tint(.frSwitchOn)
                    .disabled(lock.biometryType == .none && !lock.isEnabled)
                NavigationLink { ProfilePrivacyView(unitName: profile.units.first?.name) } label: {
                    ListRow("Datenschutz", systemImage: "hand.raised")
                }
            } header: {
                Text("App")
            } footer: {
                Text(unlockFootnote)
            }
            .listRowBackground(Color.frSurfaceContainerLow)
            Section("Konto") {
                ForEach(profile.units) { unit in
                    ListRow("Einheit · Bezirk \(unit.district)", systemImage: "building.2", value: "\(unit.name)")
                        .accessibilityElement(children: .combine)
                }
                if !profile.participants.isEmpty {
                    NavigationLink { TransferInfoView() } label: {
                        ListRow("Konto aufs Kind übertragen", systemImage: "person.2")
                    }
                }
                Button(role: .destructive) { confirmSignOut = true } label: {
                    ListRow("Abmelden", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive)
                }
                .disabled(signingOut)
                .accessibilityFocused($signOutFocused)
            }
            .listRowBackground(Color.frSurfaceContainerLow)
        }
        .scrollContentBackground(.hidden)
        .alert("Abmelden?", isPresented: $confirmSignOut) {
            Button("Abbrechen", role: .cancel) {}
            Button("Abmelden", role: .destructive) {
                signingOut = true
                Task { await SignOut.perform(model: model, lock: lock) }
            }
        } message: {
            Text("Danach brauchst du wieder Benutzername und Passwort.")
        }
        .onChange(of: confirmSignOut) { _, shown in if !shown { signOutFocused = true } }
        .onAppear { unlockOn = lock.isEnabled }
        .onChange(of: unlockOn) { _, wanted in
            guard wanted != lock.isEnabled else { return }
            if wanted {
                Task { if await !lock.enable() { unlockOn = false } }
            } else {
                lock.disable()
            }
        }
        .task(id: profile.participants.compactMap(\.badge?.imagePath)) { await loadBadges(profile) }
    }

    private var unlockTitle: LocalizedStringResource {
        lock.biometryType == .touchID ? "Mit Touch ID entsperren" : "Mit Face ID entsperren"
    }

    private var unlockSymbol: String { lock.biometryType == .touchID ? "touchid" : "faceid" }

    private var unlockFootnote: LocalizedStringResource {
        switch lock.biometryType {
        case .touchID: "Beim Start und nach 30 Sekunden im Hintergrund fragt die App nach Touch ID. Ändert sich Touch ID auf dem Gerät, meldest du dich neu an."
        case .none: "Richte zuerst Face ID oder Touch ID in den Einstellungen des iPhones ein."
        default: "Beim Start und nach 30 Sekunden im Hintergrund fragt die App nach Face ID. Ändert sich Face ID auf dem Gerät, meldest du dich neu an."
        }
    }

    private func load() async {
        loadFailed = false
        switch await model.api.me() {
        case .ok(let profile): model.profile = profile
        case .failure: loadFailed = true
        }
    }

    private func loadBadges(_ profile: Profile) async {
        for path in profile.participants.compactMap(\.badge?.imagePath) where badges[path] == nil {
            if case .ok(let data) = await model.api.badgeImage(path: path) { badges[path] = data }
        }
    }
}

private struct ChildRow: View {
    let child: ProfileParticipant
    let badge: Data?

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Avatar(initials: initials, style: .calm)
            Text(verbatim: "\(child.firstName) \(child.lastName)").foregroundStyle(Color.frOnSurface)
            Spacer(minLength: Spacing.s2)
            if let stars = child.badge?.stars {
                RangAbzeichen(badge, width: 28, stars: stars)
            } else if child.badge != nil {
                RangAbzeichen(badge, width: 28)
            }
        }
        .frame(minHeight: Sizes.touchTarget)
        .accessibilityElement(children: .combine)
    }

    private var initials: String { String([child.firstName.first, child.lastName.first].compactMap { $0 }) }
}

#if DEBUG
private struct ProfilePreviewStore: SessionStore {
    func read() -> String? { nil }
    func write(_ cookie: String) {}
    func clear() {}
}

private struct ProfilePreviewAuthenticator: BiometricAuthenticating {
    var biometryType: LABiometryType { .faceID }
    var domainState: Data? { Data([7]) }
    func authenticate(reason: String) async -> BiometricOutcome { .success }
}

private struct ProfilePreviewLockStore: LockStore {
    func read() -> Data? { nil }
    func write(_ baseline: Data) {}
    func clear() {}
}

@MainActor private func previewModel(parent: Bool, units: Int = 1) -> AppModel {
    let model = AppModel(api: FireResponseAPI(client: .live(store: ProfilePreviewStore())))
    model.profile = ProfilePreviewData.profile(parent: parent, units: units)
    model.phase = .ready
    return model
}

@MainActor private func previewLock() -> AppLockController {
    AppLockController(authenticator: ProfilePreviewAuthenticator(), store: ProfilePreviewLockStore())
}

#Preview("Eltern, Nacht, AX5") {
    ProfileRootView().environment(previewModel(parent: true)).environment(previewLock())
        .preferredColorScheme(.dark).dynamicTypeSize(.accessibility5)
}
#Preview("Eltern, Tag") {
    ProfileRootView().environment(previewModel(parent: true)).environment(previewLock()).preferredColorScheme(.light)
}
#Preview("Leitung, zwei Einheiten, Nacht") {
    ProfileRootView().environment(previewModel(parent: false, units: 2)).environment(previewLock()).preferredColorScheme(.dark)
}
#endif
