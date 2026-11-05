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

/// Die zwei Tabs der App: Übungen und Profil.
struct MainTabs: View {
    var body: some View {
        TabView {
            Tab("Übungen", systemImage: "calendar") { ExercisesRootView() }
            Tab("Profil", systemImage: "person.crop.circle") { ProfileRootView() }
        }
        // Das System fragt nur einmal; die Tabs erscheinen erst nach dem Willkommen.
        .task { await PushCenter.shared.requestAuthorization() }
    }
}
