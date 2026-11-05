import SwiftUI

/// Willkommen: Einführung, Kinder des Kontos und die Einwilligung zum Datenschutz (nur hier).
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var agreed = false
    @State private var showHint = false
    @State private var error: FormError?
    @State private var showPrivacy = false
    @AccessibilityFocusState private var rowFocused: Bool
    @AccessibilityFocusState private var noticeFocused: Bool

    private var participants: [ProfileParticipant] { model.profile?.participants ?? [] }
    private var firstName: String { (model.profile?.name ?? "").split(separator: " ").first.map(String.init) ?? "" }
    private var unitName: String {
        let names = (model.profile?.units ?? []).map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? String(localized: "Jugend- und Kinderfeuerwehr") : names.joined(separator: ", ")
    }

    var body: some View {
        OnboardingPage {
            Color.clear.frame(height: 120)
            if model.passwordJustSaved { SavedChip() }
            Eyebrow(text: Text(verbatim: unitName), color: .frOnSurface)
            FocusedTitle(firstName.isEmpty ? Text("Willkommen!") : Text("Willkommen, \(firstName)!"))
            if !participants.isEmpty { children }
            introPoints
            consentSection
            if showHint && !agreed {
                Notice(.warning, title: "Bitte bestätige zuerst den Datenschutz.")
            }
            if let error {
                Notice(.error, title: error.title, message: error.message).accessibilityFocused($noticeFocused)
            }
            FRButton("Los geht’s", action: start)
            CantonFooter().frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack { PrivacyView(api: model.api, unitName: unitName) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Abschnitte

    private var children: some View {
        let onlyChildren = participants.allSatisfy { $0.kind == "eltern" }
        return VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(onlyChildren ? "Deine Kinder" : "Deine Teilnehmenden")
                .font(.headline).foregroundStyle(Color.frOnSurface)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(participants) { participant in
                    ParticipantRow(api: model.api, participant: participant)
                    if participant.id != participants.last?.id { Divider().overlay(Color.frOutlineVariant) }
                }
            }
            .padding(.horizontal, Spacing.s4)
            .background(Color.frSurfaceContainerLow, in: RoundedRectangle(radius: Radius.md))
            .overlay(RoundedRectangle(radius: Radius.md).stroke(Color.frOutlineVariant, lineWidth: 1))
        }
    }

    private var introPoints: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            IconPoint(
                systemImage: "calendar", title: "Übungen",
                text: participants.isEmpty
                    ? Text("Alle Übungen deiner Einheit auf einen Blick.")
                    : Text("Alle Anlässe von \(Self.joined(participants.map(\.firstName))) auf einen Blick.")
            )
            IconPoint(systemImage: "checkmark.circle", title: "Zusagen", text: Text("Mit einem Tipp Ja oder Nein sagen."))
        }
    }

    private var consentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("Einwilligung").font(.headline).foregroundStyle(Color.frOnSurface).accessibilityAddTraits(.isHeader)
            if let text = model.consent?.text {
                Text(text).font(.subheadline).foregroundStyle(Color.frOnSurface)
                    .padding(Spacing.s4).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.frSurfaceContainerLow, in: RoundedRectangle(radius: Radius.md))
                    .overlay(RoundedRectangle(radius: Radius.md).stroke(Color.frOutlineVariant, lineWidth: 1))
            }
            Button { agreed.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                    Image(systemName: agreed ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(agreed ? Color.frAccent : .frOutline).accessibilityHidden(true)
                    Text("Ich habe die Datenschutzerklärung gelesen und bin einverstanden.")
                        .multilineTextAlignment(.leading).foregroundStyle(Color.frOnSurface)
                }
                .frame(maxWidth: .infinity, minHeight: Sizes.touchTarget, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isToggle)
            .accessibilityValue(agreed ? Text("Ausgewählt") : Text("Nicht ausgewählt"))
            .accessibilityFocused($rowFocused)
            Button { showPrivacy = true } label: {
                Label("Datenschutzerklärung lesen", systemImage: "hand.raised")
                    .foregroundStyle(Color.frAccent).fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: Sizes.touchTarget, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Aktion

    private func start() {
        guard agreed else {
            showHint = true
            rowFocused = true
            return
        }
        Task {
            error = await model.acceptConsent()
            if error != nil { noticeFocused = true }
        }
    }

    /// «Lena», «Lena und Noah», «Lena, Noah und Mia».
    static func joined(_ names: [String]) -> String {
        names.count <= 1 ? names.joined() : names.dropLast().joined(separator: ", ") + " und " + (names.last ?? "")
    }
}

/// «Passwort gespeichert» als Chip mit Symbol und Wort; wird angesagt.
private struct SavedChip: View {
    var body: some View {
        Label("Passwort gespeichert", systemImage: "checkmark")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.frOnSuccessContainer)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(Color.frSuccessContainer, in: .capsule)
            .onAppear { AccessibilityNotification.Announcement(String(localized: "Passwort gespeichert")).post() }
    }
}

/// Ein Kind mit Avatar, Vorname und Rangabzeichen. Nicht bedienbar; eine Zeile für VoiceOver.
private struct ParticipantRow: View {
    let api: FireResponseAPI
    let participant: ProfileParticipant
    @State private var badgeData: Data?

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Avatar(initials: String(participant.firstName.prefix(1)), style: .calm)
            Text(participant.firstName).font(.body.weight(.semibold)).foregroundStyle(Color.frOnSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let badge = participant.badge { RangAbzeichen(badgeData, width: 28, stars: badge.stars) }
        }
        .padding(.vertical, Spacing.s2)
        .accessibilityElement(children: .combine)
        .task {
            if let path = participant.badge?.imagePath { badgeData = await api.badgeImage(path: path).value }
        }
    }
}
