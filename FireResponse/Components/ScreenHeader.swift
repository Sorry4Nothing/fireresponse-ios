import SwiftUI

/// Titel mit Zusatzzeile im Inhalt. Der Titel ist eine Überschrift und bekommt nach der Navigation den VoiceOver-Fokus.
struct ScreenHeader: View {
    /// `large` wie Large Title (34 pt), `content` für lange Titel (28 pt, bis zu zwei Zeilen).
    enum Style { case large, content }

    let title: LocalizedStringResource
    var subtitle: LocalizedStringResource?
    var style: Style = .large
    @AccessibilityFocusState private var titleFocused: Bool

    init(_ title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil, style: Style = .large) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(title)
                .font(style == .large ? .frLargeTitle : .frTitle1)
                .foregroundStyle(Color.frOnSurface)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            if let subtitle {
                Text(subtitle).font(.subheadline.weight(.semibold)).foregroundStyle(Color.frOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { titleFocused = true }
    }
}

#if DEBUG
private struct ScreenHeaderDemo: View {
    var body: some View {
        VStack(spacing: Spacing.s6) {
            ScreenHeader("Anmeldungen", subtitle: "Schläuche kuppeln · Sa 14.11.")
            ScreenHeader("Eigenes Passwort wählen", subtitle: "Erster Login", style: .content)
        }
    }
}

#Preview("Nacht, AX5") { ScreenHeaderDemo().frPreview(.dark) }
#Preview("Tag, AX5") { ScreenHeaderDemo().frPreview(.light) }
#endif
