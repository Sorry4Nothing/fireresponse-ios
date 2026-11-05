import SwiftUI

/// Login mit Benutzername und Passwort. Die Einheit steckt im Konto und wird vom Server bestimmt: kein Feld dafür.
struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var username = ""
    @State private var password = ""
    @State private var error: FormError?
    @State private var showForgotHint = false
    @AccessibilityFocusState private var noticeFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        CantonCrest().padding(.bottom, Spacing.s2)
                        Eyebrow(text: Text("Jugend- und Kinderfeuerwehr"))
                        FocusedTitle(Text("Schön, bist du da."))
                    }
                    .padding(.horizontal, Spacing.s4)
                    .padding(.top, 120)
                    .padding(.bottom, Spacing.s6)
                    .frame(maxWidth: Sizes.contentMax, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .flameBackdrop()
                    Spacer(minLength: 0)
                    panel
                }
                .frame(minHeight: proxy.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(alignment: .bottom) { Color.frSurfaceContainerLow.frame(height: 40).ignoresSafeArea(edges: .bottom) }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            if let error {
                Notice(.error, title: error.title, message: error.message).accessibilityFocused($noticeFocused)
            }
            FRTextField("Benutzername", text: $username, contentType: .username, submitLabel: .next)
            FRPasswordField(text: $password, contentType: .password, submitLabel: .go)
                .onSubmit(signIn)
            FRButton("Anmelden", action: signIn)
            FRButton("Passwort vergessen?", kind: .text) { showForgotHint.toggle() }
                .frame(maxWidth: .infinity)
            if showForgotHint {
                Notice(.info, title: "Passwort vergessen?", message: "Dann hilft dir die Leitung deiner Einheit weiter.")
            }
            CantonFooter().frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.top, Spacing.s6)
        .padding(.bottom, Spacing.s2)
        .frame(maxWidth: Sizes.contentMax)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Radius.xl, topTrailingRadius: Radius.xl, style: .continuous)
                .fill(Color.frSurfaceContainerLow)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func signIn() {
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            error = .missingCredentials
            noticeFocused = true
            return
        }
        Task {
            error = await model.signIn(username: username, password: password)
            if error != nil { noticeFocused = true } else { password = "" }
        }
    }
}
