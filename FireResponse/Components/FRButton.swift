import SwiftUI

/// Kapselbutton: Haupt (Signalrot, die eine Hauptaktion pro Screen), Umriss und Text.
struct FRButton: View {
    enum Kind { case main, outline, text }

    let title: LocalizedStringResource
    var systemImage: String?
    var kind: Kind = .main
    let action: () -> Void

    init(_ title: LocalizedStringResource, systemImage: String? = nil, kind: Kind = .main, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            FRButtonLabel(title: title, systemImage: systemImage, kind: kind)
        }
        .buttonStyle(.plain)
    }
}

private struct FRButtonLabel: View {
    let title: LocalizedStringResource
    let systemImage: String?
    let kind: FRButton.Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: Spacing.s2) {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            Text(title).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, Spacing.s5)
        .padding(.vertical, Spacing.s2)
        .frame(maxWidth: kind == .text ? nil : .infinity, minHeight: kind == .text ? Sizes.touchTarget : Sizes.button)
        .background(kind == .main ? Color.frPrimary : .clear, in: .capsule)
        .overlay(Capsule().stroke(Color.frOutline, lineWidth: kind == .outline ? 1.5 : 0))
        .overlay(Capsule().stroke(Color.frFocus, lineWidth: isFocused ? 3 : 0))
        .contentShape(.capsule)
        .opacity(isEnabled ? 1 : 0.5)
    }

    private var foreground: Color {
        switch kind {
        case .main: .frOnPrimary
        case .outline: .frOnSurface
        case .text: .frAccent
        }
    }
}

#if DEBUG
private struct FRButtonDemo: View {
    var body: some View {
        VStack(spacing: Spacing.s3) {
            FRButton("Anmelden") {}
            FRButton("Alle Anmeldungen", systemImage: "list.bullet", kind: .outline) {}
            FRButton("Passwort vergessen?", kind: .text) {}
        }
    }
}

#Preview("Nacht, AX5") { FRButtonDemo().frPreview(.dark) }
#Preview("Tag, AX5") { FRButtonDemo().frPreview(.light) }
#endif
