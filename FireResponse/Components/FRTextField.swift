import SwiftUI

/// Eingabefeld mit sichtbarem Label darüber (50 pt, `radius-sm`, Rand `outline`).
struct FRTextField: View {
    let label: LocalizedStringResource
    @Binding var text: String
    var error: LocalizedStringResource?
    var contentType: UITextContentType?
    var submitLabel: SubmitLabel = .done
    @FocusState private var focused: Bool

    init(_ label: LocalizedStringResource, text: Binding<String>, error: LocalizedStringResource? = nil,
         contentType: UITextContentType? = nil, submitLabel: SubmitLabel = .done) {
        self.label = label
        _text = text
        self.error = error
        self.contentType = contentType
        self.submitLabel = submitLabel
    }

    var body: some View {
        FRFieldChrome(label: label, error: error, isFocused: focused) {
            TextField("", text: $text)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .focused($focused)
                .accessibilityLabel(Text(label))
        }
    }
}

/// Gemeinsamer Rahmen für Text- und Passwortfeld: Label, Feldrand (Fokus 2 pt, Fehler 2 pt) und Fehlersatz.
struct FRFieldChrome<Content: View>: View {
    let label: LocalizedStringResource
    let error: LocalizedStringResource?
    let isFocused: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.frOnSurfaceVariant)
                .accessibilityHidden(true)
            content
                .padding(.horizontal, Spacing.s4)
                .frame(minHeight: Sizes.field)
                .background(Color.frSurface, in: RoundedRectangle(radius: Radius.sm))
                .overlay {
                    RoundedRectangle(radius: Radius.sm).stroke(borderColor, lineWidth: isFocused || error != nil ? 2 : 1)
                }
            if let error {
                Label { Text(error) } icon: { Image(systemName: "exclamationmark.triangle") }
                    .font(.subheadline)
                    .foregroundStyle(Color.frOnErrorContainer)
            }
        }
        .onChange(of: error != nil) { _, hasError in
            if let error, hasError { AccessibilityNotification.Announcement(String(localized: error)).post() }
        }
    }

    private var borderColor: Color {
        error != nil ? .frOnErrorContainer : (isFocused ? .frFocus : .frOutline)
    }
}

#if DEBUG
private struct FRTextFieldDemo: View {
    @State private var name = "anna.muster"
    @State private var empty = ""
    var body: some View {
        VStack(spacing: Spacing.s4) {
            FRTextField("Benutzername", text: $name, contentType: .username)
            FRTextField("Benutzername", text: $empty, error: "Bitte gib deinen Benutzernamen ein.")
        }
    }
}

#Preview("Nacht, AX5") { FRTextFieldDemo().frPreview(.dark) }
#Preview("Tag, AX5") { FRTextFieldDemo().frPreview(.light) }
#endif
