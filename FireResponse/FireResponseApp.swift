import SwiftUI

@main
struct FireResponseApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var appDelegate
    @State private var model = AppModel(api: FireResponseAPI(client: Self.makeClient()))

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.run() }
        }
    }

    private static func makeClient() -> ApiClient {
        #if DEBUG
        if DebugFakeBackend.isRequested { return DebugFakeBackend.makeClient() }
        #endif
        return .live(store: KeychainSessionStore())
    }
}
