import SwiftUI

/// «Eigenes Passwort wählen»: Pflicht nach dem ersten Login. Kein Zurück, keine Tab Bar.
struct PasswordChangeView: View {
    @Environment(AppModel.self) private var model
    @State private var current = ""
    @State private var new = ""
    @State private var repeated = ""
    @State private var error: FormError?
    @State private var attempted = false
    @AccessibilityFocusState private var noticeFocused: Bool

    private var rules: PasswordRules {
        PasswordRules(new: new, repeated: repeated, current: current, username: model.username)
    }

    var body: some View {
        OnboardingPage {
            ScreenHeader("Eigenes Passwort wählen", subtitle: "Erster Login", style: .content)
                .padding(.top, 120)
            Text("Du hast ein Startpasswort von deiner Leitung bekommen. Wähle jetzt ein eigenes, das nur du kennst.")
                .foregroundStyle(Color.frOnSurface)
            if let message = formMessage {
                Notice(.error, title: message.title, message: message.message).accessibilityFocused($noticeFocused)
            }
            if !model.knowsStartPassword {
                FRPasswordField("Startpasswort", text: $current, contentType: .password, submitLabel: .next)
            }
            FRPasswordField("Neues Passwort", text: $new, contentType: .newPassword, submitLabel: .next)
            RuleList(rules: rules)
            FRPasswordField("Passwort wiederholen", text: $repeated, error: mismatch, contentType: .newPassword, submitLabel: .go)
                .onSubmit(save)
            if rules.matches {
                Label("Stimmt überein", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(Color.frOnSurface)
            }
            FRButton("Passwort speichern", action: save)
        }
        .onChange(of: rules.longEnough) { _, met in announce("Mindestens 12 Zeichen", met: met) }
        .onChange(of: rules.notUsername) { _, met in announce("Nicht dein Benutzername", met: met) }
        .onChange(of: rules.notStartPassword) { _, met in announce("Nicht das Startpasswort", met: met) }
    }

    /// Server- oder Eingabefehler als Hinweis über den Feldern.
    private var formMessage: (title: LocalizedStringResource, message: LocalizedStringResource)? {
        if let error { return (error.title, error.message) }
        if attempted && !rules.allMet { return ("Passwort speichern hat nicht geklappt", "Prüfe die Regeln unter dem neuen Passwort.") }
        if attempted && !model.knowsStartPassword && current.isEmpty { return ("Passwort speichern hat nicht geklappt", "Gib dein Startpasswort ein.") }
        return nil
    }

    private var mismatch: LocalizedStringResource? {
        attempted && !repeated.isEmpty && new != repeated ? "Die beiden Passwörter sind nicht gleich." : nil
    }

    private func announce(_ rule: String, met: Bool) {
        let state = met ? String(localized: "erfüllt") : String(localized: "nicht erfüllt")
        AccessibilityNotification.Announcement("\(rule), \(state)").post()
    }

    private func save() {
        attempted = true
        error = nil
        guard rules.canSave, model.knowsStartPassword || !current.isEmpty else {
            noticeFocused = true
            return
        }
        Task {
            error = await model.changePassword(current: model.knowsStartPassword ? nil : current, new: new)
            if error != nil { noticeFocused = true }
        }
    }
}

/// Die Regeln als Liste: jede mit Symbol und Wort (nie nur Farbe).
private struct RuleList: View {
    let rules: PasswordRules

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            row("Mindestens 12 Zeichen", met: rules.longEnough)
            row("Nicht dein Benutzername", met: rules.notUsername)
            row("Nicht das Startpasswort", met: rules.notStartPassword)
        }
    }

    private func row(_ title: LocalizedStringResource, met: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? Color.frAccent : .frOnSurfaceVariant)
                .accessibilityHidden(true)
            Text(title).font(.subheadline).foregroundStyle(Color.frOnSurface)
        }
        .frame(minHeight: 28, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(met ? Text("erfüllt") : Text("nicht erfüllt"))
    }
}
