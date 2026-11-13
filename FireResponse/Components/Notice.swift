import SwiftUI

/// Hinweis im Inhalt für Fehler, Info und Warnung (ersetzt die Snackbar). Ein Fehler wird beim Erscheinen angesagt;
/// den VoiceOver-Fokus setzt der Aufrufer mit `.accessibilityFocused(_:)`.
struct Notice: View {
    enum Kind { case error, info, warning }

    let kind: Kind
    let title: LocalizedStringResource
    var message: LocalizedStringResource?
    /// Gesetzt: der Hinweis lässt sich schliessen.
    var onDismiss: (() -> Void)?

    init(_ kind: Kind, title: LocalizedStringResource, message: LocalizedStringResource? = nil, onDismiss: (() -> Void)? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            Image(systemName: kind == .info ? "info.circle" : "exclamationmark.triangle").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                if let message { Text(message) }
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark") }
                    .accessibilityLabel("Hinweis schliessen").frame(minWidth: Sizes.touchTarget, minHeight: Sizes.touchTarget)
            }
        }
        .font(.subheadline)
        .foregroundStyle(foreground)
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(radius: Radius.md))
        .accessibilityElement(children: .combine)
        .onAppear {
            if kind == .error { AccessibilityNotification.Announcement(String(localized: title)).post() }
        }
    }

    private var background: Color {
        switch kind {
        case .error: .frErrorContainer
        case .info: .frSecondaryContainer
        case .warning: .frWarningContainer
        }
    }

    private var foreground: Color {
        switch kind {
        case .error: .frOnErrorContainer
        case .info: .frOnSecondaryContainer
        case .warning: .frOnWarningContainer
        }
    }
}

#if DEBUG
private struct NoticeDemo: View {
    var body: some View {
        VStack(spacing: Spacing.s3) {
            Notice(.error, title: "Anmelden hat nicht geklappt", message: "Benutzername oder Passwort stimmt nicht.")
            Notice(.warning, title: "Bitte prüfen", message: "Diese Person hat keine Antwort gesendet.")
            Notice(.info, title: "Nur für dich sichtbar")
        }
    }
}

#Preview("Nacht, AX5") { NoticeDemo().frPreview(.dark) }
#Preview("Tag, AX5") { NoticeDemo().frPreview(.light) }
#endif
