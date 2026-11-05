import SwiftUI

/// Titel der Start-Screens: Überschrift mit dem VoiceOver-Fokus nach der Navigation.
struct FocusedTitle: View {
    let text: Text
    var font: Font = .frDisplay
    @AccessibilityFocusState private var focused: Bool

    init(_ text: Text, font: Font = .frDisplay) {
        self.text = text
        self.font = font
    }

    var body: some View {
        text
            .font(font)
            .foregroundStyle(Color.frOnSurface)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($focused)
            .task { focused = true }
    }
}

/// Überzeile über dem Titel (nur auf Login, Start und Willkommen).
struct Eyebrow: View {
    let text: Text
    var color: Color = .frAccent

    var body: some View {
        text.font(.subheadline.weight(.bold)).foregroundStyle(color).textCase(.uppercase)
    }
}

/// Gemeinsamer Rahmen: zentrierter Inhalt (höchstens `content-max`) in einem Scroll-Bereich, Flamme im Hintergrund.
struct OnboardingPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) { content }
                .padding(.horizontal, Spacing.s4)
                .padding(.bottom, Spacing.s6)
                .frame(maxWidth: Sizes.contentMax, alignment: .leading)
                .frame(maxWidth: .infinity)
                .flameBackdrop()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.frSurface)
    }
}

/// Zeile mit rundem Symbol und Text («Übungen», «Zusagen»).
struct IconPoint: View {
    let systemImage: String
    let title: LocalizedStringResource
    let text: Text
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = Sizes.touchTarget

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.frAccent)
                .frame(width: circle, height: circle)
                .background(Color.frSurfaceContainerHigh, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(Color.frOnSurface)
                text.font(.subheadline).foregroundStyle(Color.frOnSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Sperre über dem ganzen Start-Ablauf, solange eine Aktion läuft. Sagt es an, damit VoiceOver nicht ins Leere läuft.
struct BusyOverlay: View {
    var body: some View {
        VStack(spacing: Spacing.s3) {
            ProgressView().controlSize(.large)
            Text("Einen Moment …").font(.subheadline.weight(.semibold)).foregroundStyle(Color.frOnSurface)
        }
        .padding(Spacing.s6)
        .background(Color.frSurfaceContainerHigh, in: RoundedRectangle(radius: Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear { AccessibilityNotification.Announcement(String(localized: "Einen Moment …")).post() }
    }
}
