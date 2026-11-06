import SwiftUI

/// Logo einer Einheit; ohne Logo (404, nicht lesbar, SVG kann `UIImage` nicht) steht das Kürzel «JF» oder «KF» im Kreis.
/// Dekoration: Der Name der Einheit steht im Satz der Zeile, das Bild trägt nie allein die Information.
struct UnitMark: View {
    /// Platz, den Texte neben dem Logo auf einer Karte frei lassen.
    static let reservedWidth: CGFloat = 52

    let uiImage: UIImage?
    let type: String
    /// `false` solange das Logo noch lädt: der Platz bleibt frei.
    let settled: Bool
    @ScaledMetric private var side: CGFloat

    init(data: Data?, type: String, settled: Bool, size: CGFloat = 40) {
        uiImage = data.flatMap(UIImage.init(data:))
        self.type = type
        self.settled = settled
        _side = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage).resizable().scaledToFit()
            } else if settled {
                Text(type == "kf" ? "KF" : "JF")
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(Color.frOnSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.frSurfaceContainerHigh, in: .circle)
            } else {
                Color.clear
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
