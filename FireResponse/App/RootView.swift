import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.phase == .ready {
                MainTabs()
            } else {
                OnboardingRootView()
            }
        }
        .tint(.frAccent)
        .appLock()
        .pushRegistration()
    }
}

/// Die Tabs der App: Übungen, Infokanal und Profil.
struct MainTabs: View {
    @Environment(AppModel.self) private var app

    var body: some View { MainTabsContent(service: app.api) }
}

private struct MainTabsContent: View {
    enum Item { case exercises, info, profile }

    @State private var selection: Item = .exercises
    @State private var channels: InfoChannelsModel
    private let router = PushCenter.shared.router

    init(service: any InfoChannelService) {
        _channels = State(initialValue: InfoChannelsModel(service: service))
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Übungen", systemImage: "calendar", value: Item.exercises) { ExercisesRootView() }
            Tab("Infokanal", systemImage: "megaphone", value: Item.info) { InfoChannelRootView(model: channels) }
                .badge(channels.unreadTotal)
            Tab("Profil", systemImage: "person.crop.circle", value: Item.profile) { ProfileRootView() }
        }
        .task { await channels.load() }
        // Ein angetippter Push zum Infokanal wechselt auf den Reiter; der Verlauf öffnet dort.
        .onChange(of: router.pendingInfoChannel, initial: true) { if router.pendingInfoChannel != nil { selection = .info } }
        // Das System fragt nur einmal; die Tabs erscheinen erst nach dem Willkommen.
        .task { await PushCenter.shared.requestAuthorization() }
    }
}
