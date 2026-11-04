import SwiftUI

@main
struct FireResponseApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate
    @State private var model = AppModel(api: FireResponseAPI(client: .live(store: KeychainSessionStore())))

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
