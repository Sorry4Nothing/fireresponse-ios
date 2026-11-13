import SwiftUI

/// Texte des Wartungsbildschirms. Der Text des Betreibers (höchstens 280 Zeichen) steht, wenn es einen gibt; sonst der Standardtext,
/// mit dem voraussichtlichen Ende, wenn der Server es nennt.
nonisolated enum MaintenanceText {
    static func message(for info: MaintenanceInfo, now: Date = .now) -> String {
        if let text = info.text {
            guard let until = info.until else { return text }
            return "\(text) \(String(localized: "Voraussichtlich bis \(endText(until, now: now))."))"
        }
        if let until = info.until {
            return String(localized: "FireResponse wird gerade gewartet, voraussichtlich bis \(endText(until, now: now)). Deine Zusagen bleiben gespeichert.")
        }
        return String(localized: "FireResponse wird gerade gewartet. Bitte versuche es später noch einmal.")
    }

    /// «22:00 Uhr» am selben Tag, sonst «Samstag, 14. November, 08:00 Uhr» (Schweizer Zeit).
    static func endText(_ until: Date, now: Date) -> String {
        let day = SwissDay(date: until)
        let time = String(localized: "\(ExerciseFormat.time(until)) Uhr")
        return day == SwissDay(date: now) ? time : "\(ExerciseFormat.longDay(day)), \(time)"
    }
}

/// Wartung (Issue #64): ganzseitig, ruhig, kein Alarm. Es liegt nicht am Gerät und nicht am Konto; es kommt wieder.
/// «Erneut prüfen» fragt den öffentlichen Status, es gibt keine Dauerabfrage.
struct MaintenanceView: View {
    let info: MaintenanceInfo
    let check: AppModel.MaintenanceCheck
    let recheck: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.s4) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title)
                    .foregroundStyle(Color.frOnSecondaryContainer)
                    .frame(width: 72, height: 72)
                    .background(Color.frSecondaryContainer, in: .circle)
                    .accessibilityHidden(true)
                Text("Wartungsarbeiten").font(.frTitle2).foregroundStyle(Color.frOnSurface).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Text(verbatim: MaintenanceText.message(for: info)).font(.body).foregroundStyle(Color.frOnSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                switch check {
                case .stillOn: Notice(.info, title: "Die Wartung läuft noch.", message: "Versuche es später noch einmal.")
                case .offline: Notice(.error, title: "Keine Verbindung.", message: "Prüfe dein Internet und versuche es nochmals.")
                case .idle, .checking: EmptyView()
                }
                FRButton(check == .checking ? "Wird geprüft …" : "Erneut prüfen", systemImage: "arrow.clockwise", action: recheck)
                    .disabled(check == .checking)
                    .frame(maxWidth: Sizes.contentMax)
            }
            .padding(Spacing.s6)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center, for: .alignment)
        .background(Color.frSurface.ignoresSafeArea())
        .onAppear { titleFocused = true }
        .onChange(of: check) { _, state in
            if state == .stillOn { AccessibilityNotification.Announcement(String(localized: "Die Wartung läuft noch.")).post() }
        }
    }
}

#if DEBUG
#Preview("Mit Ende, Nacht, AX5") {
    MaintenanceView(info: MaintenanceInfo(text: nil, until: .now.addingTimeInterval(3600)), check: .idle, recheck: {})
        .preferredColorScheme(.dark).dynamicTypeSize(.accessibility5)
}
#Preview("Ohne Ende, Tag") {
    MaintenanceView(info: MaintenanceInfo(text: nil, until: nil), check: .stillOn, recheck: {}).preferredColorScheme(.light)
}
#Preview("Eigener Text, Nacht, offline") {
    MaintenanceView(info: MaintenanceInfo(text: "Wir führen ein Update durch.", until: nil), check: .offline, recheck: {})
        .preferredColorScheme(.dark)
}
#endif
