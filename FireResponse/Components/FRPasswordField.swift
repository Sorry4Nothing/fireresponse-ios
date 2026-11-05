import SwiftUI

/// Passwortfeld mit Auge-Button (44 pt, «Passwort anzeigen» / «Passwort verbergen»).
struct FRPasswordField: View {
    let label: LocalizedStringResource
    @Binding var text: String
    var error: LocalizedStringResource?
    var contentType: UITextContentType = .password
    var submitLabel: SubmitLabel = .done
    @State private var isRevealed = false
    @FocusState private var focused: Bool

    init(_ label: LocalizedStringResource = "Passwort", text: Binding<String>, error: LocalizedStringResource? = nil,
         contentType: UITextContentType = .password, submitLabel: SubmitLabel = .done) {
        self.label = label
        _text = text
        self.error = error
        self.contentType = contentType
        self.submitLabel = submitLabel
    }

    var body: some View {
        FRFieldChrome(label: label, error: error, isFocused: focused) {
            HStack(spacing: Spacing.s2) {
                Group {
                    if isRevealed { TextField("", text: $text) } else { SecureField("", text: $text) }
                }
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .focused($focused)
                .accessibilityLabel(Text(label))
                Button {
                    isRevealed.toggle()
                    focused = true
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(Color.frOnSurfaceVariant)
                        .frame(width: Sizes.touchTarget, height: Sizes.touchTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? Text("Passwort verbergen") : Text("Passwort anzeigen"))
            }
        }
    }
}

#if DEBUG
private struct FRPasswordFieldDemo: View {
    @State private var secret = "geheim-geheim"
    var body: some View {
        FRPasswordField(text: $secret, contentType: .newPassword)
    }
}

#Preview("Nacht, AX5") { FRPasswordFieldDemo().frPreview(.dark) }
#Preview("Tag, AX5") { FRPasswordFieldDemo().frPreview(.light) }
#endif
