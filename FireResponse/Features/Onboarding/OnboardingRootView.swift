import SwiftUI

/// Alles vor den Übungen: Start, Login, Passwort, Willkommen und die Zustände «Keine Einheit» und «Sitzung abgelaufen».
/// Als Vollbild ohne Tab Bar (Design: Erster Start als `fullScreenCover`). Die Phase kommt aus `AppModel`.
struct OnboardingRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.frSurface.ignoresSafeArea()
            switch model.phase {
            case .launching, .ready: StartView()
            case .signedOut: LoginView()
            case .sessionExpired: SessionExpiredView()
            case .passwordChange: PasswordChangeView()
            case .welcome: WelcomeView()
            case .noUnit: NoUnitView()
            }
        }
        // Globale Ladesperre: Während einer Aktion nimmt nichts Eingaben an.
        .disabled(model.isBusy)
        .overlay { if model.isBusy && model.phase != .launching { BusyOverlay() } }
    }
}

/// Zustand «Sitzung abgelaufen» (nach 401): ohne Leiste, Aktion «Anmelden».
private struct SessionExpiredView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView { StateView(.sessionExpired) { model.backToLogin() } }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear { AccessibilityNotification.ScreenChanged().post() }
    }
}

/// Zustand «Keine Einheit»: «Zurück zum Login» meldet ab und löscht alles.
private struct NoUnitView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView { StateView(.noUnit) { Task { await model.signOut() } } }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear { AccessibilityNotification.ScreenChanged().post() }
    }
}

/// Start: Flamme, Wappen, Überzeile und «FireResponse» mit Ladebalken; scheitert der Start, der Fehler mit «Nochmals versuchen».
struct StartView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var noticeFocused: Bool

    var body: some View {
        OnboardingPage {
            Color.clear.frame(height: 110)
            CantonCrest()
            Eyebrow(text: Text("Jugend- und Kinderfeuerwehr"))
            FocusedTitle(Text("FireResponse"))
            if let error = model.startError {
                if error == .offline {
                    StateView(.offline) { Task { await model.start() } }
                } else {
                    Notice(.error, title: error.title, message: error.message)
                        .accessibilityFocused($noticeFocused)
                    FRButton("Nochmals versuchen", systemImage: "arrow.clockwise") { Task { await model.start() } }
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    if !reduceMotion { ProgressView().progressViewStyle(.linear).tint(.frAccent) }
                    Text("Wird geladen …").font(.subheadline).foregroundStyle(Color.frOnSurfaceVariant)
                }
                .accessibilityElement(children: .combine)
            }
            CantonFooter()
        }
        .onChange(of: model.startError) { _, error in noticeFocused = error != nil && error != .offline }
    }
}
