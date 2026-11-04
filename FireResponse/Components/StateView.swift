import SwiftUI

/// Ganzseitiger Zustand: rundes Symbol, Titel, ein Satz und höchstens zwei Buttons.
/// Fehlt eine Aktion (`nil`), fehlt der Button. `primary` ist die Hauptaktion des Zustands, `secondary` nur bei «Fehler».
struct StateView: View {
    enum Kind: CaseIterable {
        case loading, empty, offline, error, notFound, noAccess, sessionExpired, noUnit
    }

    let kind: Kind
    var primary: (() -> Void)?
    var secondary: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ kind: Kind, primary: (() -> Void)? = nil, secondary: (() -> Void)? = nil) {
        self.kind = kind
        self.primary = primary
        self.secondary = secondary
    }

    var body: some View {
        if kind == .loading {
            Skeleton()
        } else {
            VStack(spacing: Spacing.s4) {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(kind == .error ? Color.frOnErrorContainer : .frOnSecondaryContainer)
                    .frame(width: 72, height: 72)
                    .background(kind == .error ? Color.frErrorContainer : .frSecondaryContainer, in: .circle)
                    .accessibilityHidden(true)
                Text(title).font(.frTitle2).foregroundStyle(Color.frOnSurface).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message).font(.body).foregroundStyle(Color.frOnSurfaceVariant).multilineTextAlignment(.center)
                VStack(spacing: Spacing.s3) {
                    if let primary { FRButton(primaryTitle, systemImage: primarySymbol, action: primary) }
                    if let secondary, kind == .error { FRButton("Zu den Übungen", kind: .outline, action: secondary) }
                }
                .frame(maxWidth: Sizes.contentMax)
            }
            .padding(Spacing.s6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var symbol: String {
        switch kind {
        case .loading: ""
        case .empty: "calendar"
        case .offline: "wifi.slash"
        case .notFound: "magnifyingglass"
        case .error: "exclamationmark.triangle"
        case .noAccess, .noUnit: "lock"
        case .sessionExpired: "clock"
        }
    }

    private var title: LocalizedStringResource {
        switch kind {
        case .loading: "Übungen werden geladen"
        case .empty: "Noch keine Übungen"
        case .offline: "Keine Verbindung"
        case .error: "Etwas ist schiefgelaufen"
        case .notFound: "Nicht gefunden"
        case .noAccess: "Kein Zugriff"
        case .sessionExpired: "Bitte melde dich neu an"
        case .noUnit: "Keine Einheit"
        }
    }

    private var message: LocalizedStringResource {
        switch kind {
        case .loading: ""
        case .empty: "Sobald die Leitung neue Übungen einträgt, siehst du sie hier."
        case .offline: "Prüfe dein Internet und versuche es nochmals."
        case .error: "Das liegt nicht an dir. Versuche es in ein paar Minuten nochmals."
        case .notFound: "Diese Übung gibt es nicht mehr. Vielleicht wurde sie verschoben oder abgesagt."
        case .noAccess: "Diese Seite ist nur für die Leitung deiner Einheit. Wenn du denkst, das ist ein Fehler, frag deine Leitung."
        case .sessionExpired: "Du warst länger nicht aktiv. Zu deiner Sicherheit haben wir dich abgemeldet."
        case .noUnit: "Dein Konto ist noch keiner Einheit zugewiesen. Das erledigt deine Jugendleitung. Frag dort nach."
        }
    }

    private var primaryTitle: LocalizedStringResource {
        switch kind {
        case .loading: ""
        case .empty: "Aktualisieren"
        case .offline, .error: "Nochmals versuchen"
        case .notFound, .noAccess: "Zu den Übungen"
        case .sessionExpired: "Anmelden"
        case .noUnit: "Zurück zum Login"
        }
    }

    private var primarySymbol: String? {
        switch kind {
        case .empty, .offline, .error: "arrow.clockwise"
        default: nil
        }
    }
}

/// Skelett der Zeitleiste: ruhige Flächen, kein Pulsieren und kein Schimmer.
/// VoiceOver sagt «Übungen werden geladen» erst nach einer Sekunde an, damit kurze Ladezeiten nicht stören.
private struct Skeleton: View {
    var body: some View {
        VStack(spacing: Spacing.s3) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(radius: Radius.md).fill(Color.frSurfaceContainerHigh).frame(height: 96)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Übungen werden geladen"))
        .task {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { AccessibilityNotification.Announcement(String(localized: "Übungen werden geladen")).post() }
        }
    }
}

#if DEBUG
private struct StateViewDemo: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.s6) {
                ForEach(StateView.Kind.allCases, id: \.self) { kind in
                    StateView(kind, primary: {}, secondary: {})
                }
            }
        }
    }
}

#Preview("Nacht, AX5") { StateViewDemo().frPreview(.dark) }
#Preview("Tag, normal") { StateViewDemo().frPreview(.light, size: .large) }
#endif
