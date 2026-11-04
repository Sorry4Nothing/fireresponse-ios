import SwiftUI

/// Abzeichen eines Rangs, nur als Bild und nur zur Anzeige (Seitenverhältnis 100 : 130, ohne Rangtext).
/// V1: `imageData` kommt aus `/raenge/{id}/abzeichen` (PNG; SVG liest `UIImage` nicht). Fehlt es oder ist es unlesbar,
/// zeichnet der Baustein den Platzhalter aus `Raenge.md` mit `stars` Sternen (0 bis 2).
struct RangAbzeichen: View {
    let uiImage: UIImage?
    var width: CGFloat = 28
    var stars: Int?

    init(_ imageData: Data?, width: CGFloat = 28, stars: Int? = nil) {
        uiImage = imageData.flatMap(UIImage.init(data:))
        self.width = width
        self.stars = stars
    }

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage).resizable().scaledToFit()
            } else {
                BadgePlaceholder(stars: min(max(stars ?? 0, 0), 2))
                    .frame(width: 100, height: 130)
                    .scaleEffect(width / 100, anchor: .topLeading)
            }
        }
        .frame(width: width, height: width * 1.3, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
    }

    private var label: Text {
        switch stars {
        case 1: Text("Rangabzeichen, ein Stern")
        case 2: Text("Rangabzeichen, zwei Sterne")
        default: Text("Rangabzeichen")
        }
    }
}

// Platzhalter in der Koordinatenebene 100 × 130 der SVG-Vorlage; die Farben bleiben in allen Erscheinungen gleich.
private struct BadgePlaceholder: View {
    let stars: Int
    private static let gold = Color(red: 0.91, green: 0.70, blue: 0.18)

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.04, green: 0.07, blue: 0.19))
            RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.11, green: 0.16, blue: 0.36), lineWidth: 2)
            VStack(spacing: 0) {
                Text("JUGEND")
                Text("FEUERWEHR")
            }
            .font(.custom("BarlowCondensed-Bold", fixedSize: 17))
            .foregroundStyle(Self.gold)
            .frame(width: 100)
            .offset(y: 8)
            Shield(diagonal: false).fill(.white)
            Shield(diagonal: true).fill(Color(red: 0.15, green: 0.39, blue: 0.78))
            Shield(diagonal: false).stroke(Color(red: 0.87, green: 0.91, blue: 0.98), lineWidth: 1.2)
            ForEach(0..<stars, id: \.self) { index in
                Star().fill(Self.gold).frame(width: 18, height: 18)
                    .position(x: stars == 1 ? 50 : (index == 0 ? 33 : 67), y: 115)
            }
        }
        .frame(width: 100, height: 130)
    }
}

/// Zürcher Schild (ganze Form oder blaue Diagonale) in Koordinaten der SVG-Vorlage, bereits auf 100 × 130 skaliert.
private nonisolated struct Shield: Shape {
    let diagonal: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if diagonal {
            path.move(to: CGPoint(x: 1, y: 0.98764))
            path.addLine(to: CGPoint(x: 5.3125, y: 182.67514))
            path.addCurve(to: CGPoint(x: 219.5, y: 232.76889), control1: CGPoint(x: 7.9335, y: 292.76272),
                          control2: CGPoint(x: 168.85432, y: 309.46046))
        } else {
            path.move(to: CGPoint(x: 1, y: 1))
            path.addLine(to: CGPoint(x: 5.325489, y: 182.67978))
            path.addCurve(to: CGPoint(x: 234.576860, y: 182.67978), control1: CGPoint(x: 8.415122, y: 312.45096),
                          control2: CGPoint(x: 231.487, y: 312.45096))
            path.addLine(to: CGPoint(x: 238.90236, y: 1))
        }
        path.closeSubpath()
        return path.applying(CGAffineTransform(a: 0.2, b: 0, c: 0, d: 0.1925, tx: 26, ty: 50))
    }
}

private nonisolated struct Star: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for index in 0..<10 {
            let radius = (index.isMultiple(of: 2) ? 0.5 : 0.19) * rect.width
            let angle = -Double.pi / 2 + Double(index) * .pi / 5
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

#if DEBUG
private struct RangAbzeichenDemo: View {
    var body: some View {
        HStack(spacing: Spacing.s4) {
            RangAbzeichen(nil, width: 56)
            RangAbzeichen(nil, width: 56, stars: 1)
            RangAbzeichen(nil, width: 56, stars: 2)
            RangAbzeichen(nil, width: 24)
        }
    }
}

#Preview("Nacht, AX5") { RangAbzeichenDemo().frPreview(.dark) }
#Preview("Tag, AX5") { RangAbzeichenDemo().frPreview(.light) }
#endif
