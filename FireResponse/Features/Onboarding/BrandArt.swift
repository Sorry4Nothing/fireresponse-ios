import SwiftUI

// Flamme und Wappen als Vektoren nach den SVGs des Designs (Login-Vorschau). Die Farben bleiben in allen Erscheinungen gleich.
// Die Bilder liegen (noch) nicht als Asset vor; ersetzt das Design sie, genügt es, diese Datei auszutauschen.

/// Äussere und innere Flamme (Koordinatenebene 160 × 160).
private nonisolated struct FlameShape: Shape {
    let inner: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 160 * rect.width, y: rect.minY + y / 160 * rect.height)
        }
        if inner {
            path.move(to: point(80, 78))
            path.addCurve(to: point(104, 118), control1: point(88, 92), control2: point(104, 100))
            path.addCurve(to: point(80, 142), control1: point(104, 133), control2: point(93, 142))
            path.addCurve(to: point(56, 118), control1: point(67, 142), control2: point(56, 133))
            path.addCurve(to: point(80, 78), control1: point(56, 100), control2: point(72, 92))
        } else {
            path.move(to: point(80, 10))
            path.addCurve(to: point(130, 95), control1: point(95, 40), control2: point(130, 55))
            path.addCurve(to: point(80, 148), control1: point(130, 125), control2: point(108, 148))
            path.addCurve(to: point(30, 95), control1: point(52, 148), control2: point(30, 125))
            path.addCurve(to: point(55, 42), control1: point(30, 72), control2: point(45, 58))
            path.addCurve(to: point(72, 62), control1: point(58, 56), control2: point(66, 62))
            path.addCurve(to: point(80, 10), control1: point(70, 42), control2: point(74, 26))
        }
        path.closeSubpath()
        return path
    }
}

/// Das Fire-Response-Zeichen: gross und angeschnitten im Hintergrund, nie umgefärbt. Dekoration, für VoiceOver unsichtbar.
struct FlameMark: View {
    var body: some View {
        ZStack {
            FlameShape(inner: false).fill(Color(red: 0.831, green: 0.086, blue: 0.110))
            FlameShape(inner: true).fill(Color(red: 1, green: 0.769, blue: 0))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Umriss des Zürcher Schilds (Koordinatenebene 240 × 282).
private nonisolated struct CrestShield: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 240 * rect.width, y: rect.minY + y / 282 * rect.height)
        }
        var path = Path()
        path.move(to: point(1, 1))
        path.addLine(to: point(5.325, 182.68))
        path.addCurve(to: point(234.577, 182.68), control1: point(8.415, 312.45), control2: point(231.487, 312.45))
        path.addLine(to: point(238.902, 1))
        path.closeSubpath()
        return path
    }
}

private nonisolated struct CrestDiagonal: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 240 * rect.width, y: rect.minY + y / 282 * rect.height)
        }
        var path = Path()
        path.move(to: point(1, 0.988))
        path.addLine(to: point(5.3125, 182.675))
        path.addCurve(to: point(219.5, 232.769), control1: point(7.9335, 292.763), control2: point(168.854, 309.46))
        path.closeSubpath()
        return path
    }
}

/// Wappen des Kantons Zürich. Bleibt ein Bild mit Label, der Schild ist weiss mit blauer Diagonale.
struct CantonCrest: View {
    var width: CGFloat = 48

    var body: some View {
        ZStack {
            CrestShield().fill(.white)
            CrestDiagonal().fill(Color(red: 0.153, green: 0.392, blue: 0.780)).clipShape(CrestShield())
            CrestShield().stroke(.black, lineWidth: width / 120)
        }
        .frame(width: width, height: width * 282 / 240)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Wappen Kanton Zürich"))
        .accessibilityAddTraits(.isImage)
    }
}

/// Fusszeile von Login und Willkommen: kleines Wappen mit «Kanton Zürich».
struct CantonFooter: View {
    var body: some View {
        HStack(spacing: Spacing.s2) {
            CantonCrest(width: 15).accessibilityHidden(true)
            Text("Kanton Zürich").font(.footnote).foregroundStyle(Color.frOnSurfaceVariant)
        }
        .frame(minHeight: Sizes.touchTarget)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Flamme oben rechts, angeschnitten, direkt auf `surface`. Sie gehört zum Inhalt und scrollt mit weg,
    /// damit grosse Schrift nie über ihr liegt (Kontrast).
    func flameBackdrop() -> some View {
        background(alignment: .topTrailing) {
            FlameMark()
                .frame(width: 230, height: 230)
                .offset(x: 80, y: -80)
        }
    }
}

#if DEBUG
#Preview("Nacht") {
    CantonCrest().frame(maxWidth: .infinity, maxHeight: .infinity).flameBackdrop().preferredColorScheme(.dark)
}
#Preview("Tag") {
    CantonCrest().frame(maxWidth: .infinity, maxHeight: .infinity).flameBackdrop().preferredColorScheme(.light)
}
#endif
