import SwiftUI
import WidgetKit

struct NextExercisesView: View {
    let entry: ExercisesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            switch entry.content {
            case .signedOut:
                message("Bitte melde dich in der App an.")
            case .rows(let rows) where rows.isEmpty:
                message("Keine Übungen in Sicht.")
            case .rows(let rows):
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Color.frOutlineVariant.frame(height: 1) }
                    ExerciseRow(row: row)
                }
                // Mit nur einer Übung sagt ein ruhiger Satz, dass nichts mehr folgt: So wirkt die Fläche nicht leer.
                if rows.count == 1 {
                    Text("Danach ist keine weitere Übung in Sicht.")
                        .font(.footnote)
                        .foregroundStyle(Color.frOnSurfaceVariant)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            FlameShape().frame(width: 14, height: 14)
            Text("Fire-Response · Nächste Übungen")
                .font(.caption2.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundStyle(Color.frOnSurfaceVariant)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.frOnSurface)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ExerciseRow: View {
    let row: WidgetSnapshot.Row

    var body: some View {
        // Die Zeile ist ein Element mit einem ganzen Satz; die Teile darin sind für VoiceOver ausgeblendet.
        Link(destination: WidgetLink.url(programId: row.id) ?? URL(fileURLWithPath: "/")) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.custom("BarlowCondensed-Bold", size: 17, relativeTo: .headline))
                    .foregroundStyle(Color.frOnSurface)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(row.unitType)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.frOnSecondaryMuted)
                        .padding(.horizontal, 5)
                        .frame(minHeight: 18)
                        .background(Color.frSurfaceContainerHigh, in: RoundedRectangle(cornerRadius: 5))
                    Text(row.when)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.frAccentText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let count = row.count {
                        Text(count)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.frOnSurfaceVariant)
                            .lineLimit(1)
                    }
                    PeopleView(people: row.people)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.spoken)
    }
}

/// Bis zwei Personen als Chip mit Namen, ab drei als Kreise mit Initiale (höchstens fünf; «x von y» zählt alle).
private struct PeopleView: View {
    let people: [WidgetSnapshot.Person]
    private static let maxDots = 5

    var body: some View {
        HStack(spacing: 4) {
            if people.count <= 2 {
                ForEach(Array(people.enumerated()), id: \.offset) { _, person in NameChip(person: person) }
            } else {
                ForEach(Array(people.prefix(Self.maxDots).enumerated()), id: \.offset) { _, person in InitialDot(person: person) }
            }
        }
    }
}

private struct NameChip: View {
    let person: WidgetSnapshot.Person

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: person.stand.symbol).font(.system(size: 10, weight: .heavy))
            Text(person.name).font(.caption2.weight(.bold)).lineLimit(1)
        }
        .foregroundStyle(person.stand.foreground)
        .padding(.leading, 5)
        .padding(.trailing, 7)
        .frame(minHeight: 22)
        .background(person.stand.background, in: Capsule())
    }
}

private struct InitialDot: View {
    let person: WidgetSnapshot.Person

    var body: some View {
        Text(person.name.prefix(1).uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(person.stand.foreground)
            .frame(width: 22, height: 22)
            .background(person.stand.background, in: Circle())
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: person.stand.symbol)
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(Color.frSurfaceContainerLow)
                    .frame(width: 10, height: 10)
                    .background(person.stand.foreground, in: Circle())
                    .offset(x: 3, y: 3)
            }
            .padding(.trailing, 3)
    }
}

private extension WidgetSnapshot.Stand {
    var symbol: String {
        switch self {
        case .yes: "checkmark"
        case .no: "xmark"
        case .open: "questionmark"
        }
    }

    var foreground: Color {
        switch self {
        case .yes: .frOnSuccessContainer
        case .no: .frOnErrorContainer
        case .open: .frOnSecondaryContainer
        }
    }

    var background: Color {
        switch self {
        case .yes: .frSuccessContainer
        case .no: .frErrorContainer
        case .open: .frSecondaryContainer
        }
    }
}

/// Die Flamme aus dem Entwurf (Platzhalter wie `BrandArt` in der App, bis das Design Bilder liefert).
private struct FlameShape: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / 160
            func path(_ build: (inout Path) -> Void) -> Path {
                var path = Path()
                build(&path)
                return path.applying(CGAffineTransform(scaleX: scale, y: scale))
            }
            let outer = path { p in
                p.move(to: .init(x: 80, y: 10))
                p.addCurve(to: .init(x: 130, y: 95), control1: .init(x: 95, y: 40), control2: .init(x: 130, y: 55))
                p.addCurve(to: .init(x: 80, y: 148), control1: .init(x: 130, y: 125), control2: .init(x: 108, y: 148))
                p.addCurve(to: .init(x: 30, y: 95), control1: .init(x: 52, y: 148), control2: .init(x: 30, y: 125))
                p.addCurve(to: .init(x: 55, y: 42), control1: .init(x: 30, y: 72), control2: .init(x: 45, y: 58))
                p.addCurve(to: .init(x: 72, y: 62), control1: .init(x: 58, y: 56), control2: .init(x: 66, y: 62))
                p.addCurve(to: .init(x: 80, y: 10), control1: .init(x: 70, y: 42), control2: .init(x: 74, y: 26))
                p.closeSubpath()
            }
            let inner = path { p in
                p.move(to: .init(x: 80, y: 78))
                p.addCurve(to: .init(x: 104, y: 118), control1: .init(x: 88, y: 92), control2: .init(x: 104, y: 100))
                p.addCurve(to: .init(x: 80, y: 142), control1: .init(x: 104, y: 133), control2: .init(x: 93, y: 142))
                p.addCurve(to: .init(x: 56, y: 118), control1: .init(x: 67, y: 142), control2: .init(x: 56, y: 133))
                p.addCurve(to: .init(x: 80, y: 78), control1: .init(x: 56, y: 100), control2: .init(x: 72, y: 92))
                p.closeSubpath()
            }
            context.fill(outer, with: .color(.frPrimary))
            context.fill(inner, with: .color(.frAccentFill))
        }
    }
}
