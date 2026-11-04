import SwiftUI

/// Kleines Etikett für einen Zustand, immer mit Symbol und Wort. Nicht bedienbar.
struct StatusChip: View {
    enum Kind: CaseIterable {
        case yes, no, open, review, unassigned
    }

    let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    var body: some View {
        Label { Text(title) } icon: { Image(systemName: symbol) }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(background, in: .capsule)
            .overlay(Capsule().stroke(Color.frOutline, lineWidth: kind == .open ? 1 : 0))
    }

    private var title: LocalizedStringResource {
        switch kind {
        case .yes: "Ja"
        case .no: "Nein"
        case .open: "Offen"
        case .review: "Prüfen"
        case .unassigned: "Nicht zugeordnet"
        }
    }

    private var symbol: String {
        switch kind {
        case .yes: "checkmark"
        case .no: "xmark"
        case .open: "questionmark.circle"
        case .review: "exclamationmark.triangle"
        case .unassigned: "person.crop.circle.badge.questionmark"
        }
    }

    private var background: Color {
        switch kind {
        case .yes: .frSuccessContainer
        case .no: .frErrorContainer
        case .open: .clear
        case .review: .frWarningContainer
        case .unassigned: .frSecondaryContainer
        }
    }

    private var foreground: Color {
        switch kind {
        case .yes: .frOnSuccessContainer
        case .no: .frOnErrorContainer
        case .open: .frOnSurface
        case .review: .frOnWarningContainer
        case .unassigned: .frOnSecondaryContainer
        }
    }
}

#if DEBUG
private struct StatusChipDemo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            ForEach(StatusChip.Kind.allCases, id: \.self) { StatusChip($0) }
        }
    }
}

#Preview("Nacht, AX5") { StatusChipDemo().frPreview(.dark) }
#Preview("Tag, AX5") { StatusChipDemo().frPreview(.light) }
#endif
