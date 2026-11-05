import SwiftUI

extension View {
    /// Meldet Login und Abmelden an `PushCenter` (Token beim Server hinterlegen). Einmal am Wurzel-View.
    func pushRegistration() -> some View { modifier(PushRegistrationModifier()) }
}

private struct PushRegistrationModifier: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.task(id: model.phase == .ready) { [model] in
            await PushCenter.shared.sessionChanged(api: model.api, signedIn: model.phase == .ready)
        }
    }
}
