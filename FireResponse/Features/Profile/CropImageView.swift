import SwiftUI

/// Das gewählte Foto, bevor es hochgeladen wird: `data` wird erst nach «Übernehmen» zugeschnitten.
struct CropSession: Identifiable {
    let id = UUID()
    let data: Data
    let preview: CGImage
}

/// Ausschnitt fürs Profilbild wählen (Issue #22): quadratischer Rahmen mit Kreis als Hilfslinie, Foto verschieben und zoomen.
/// Ohne Zwei-Finger-Geste bedienbar: Zoom-Regler, und VoiceOver bekommt Aktionen zum Verschieben.
struct CropImageView: View {
    let session: CropSession
    let onCancel: () -> Void
    let onDone: (ProfileImageCrop) -> Void
    @State private var crop = ProfileImageCrop()
    @State private var dragStart: ProfileImageCrop?
    @State private var zoomStart: Double?

    private var width: Int { session.preview.width }
    private var height: Int { session.preview.height }

    var body: some View {
        NavigationStack {
            // Scrollbar, damit bei der grössten Schrift nichts abgeschnitten wird.
            ScrollView {
                VStack(spacing: Spacing.s4) {
                    GeometryReader { proxy in frame(side: min(proxy.size.width, Sizes.contentMax)) }
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: Sizes.contentMax)
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Text("Zoom").font(.subheadline).foregroundStyle(Color.frOnSurfaceVariant)
                        Slider(value: zoomBinding, in: 1...ProfileImageCrop.maxZoom)
                            .tint(.frPrimary)
                            .accessibilityLabel(Text("Zoom"))
                    }
                    .frame(maxWidth: Sizes.contentMax)
                }
                .padding(Spacing.s4)
                .frame(maxWidth: .infinity)
            }
            .background(Color.frSurface)
            .navigationTitle("Ausschnitt wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) { Button("Übernehmen") { onDone(crop) } }
            }
        }
    }

    private var zoomBinding: Binding<Double> {
        Binding(get: { crop.zoom }, set: { crop = crop.zoomed(to: $0, width: width, height: height) })
    }

    private func frame(side: CGFloat) -> some View {
        let square = crop.square(width: width, height: height)
        let scale = side / square.width
        return ZStack(alignment: .topLeading) {
            Image(decorative: session.preview, scale: 1)
                .resizable()
                .frame(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
                .offset(x: -square.minX * scale, y: -square.minY * scale)
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .clipped()
        .overlay { CircleGuide().allowsHitTesting(false) }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    let start = dragStart ?? crop
                    dragStart = start
                    crop = start.moved(dx: -value.translation.width / scale, dy: -value.translation.height / scale, width: width, height: height)
                }
                .onEnded { _ in dragStart = nil }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = zoomStart ?? crop.zoom
                    zoomStart = start
                    crop = crop.zoomed(to: start * value.magnification, width: width, height: height)
                }
                .onEnded { _ in zoomStart = nil }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Foto, Ausschnitt für das Profilbild"))
        .accessibilityAddTraits(.isImage)
        .accessibilityAction(named: Text("Ausschnitt nach links")) { move(dx: -1, dy: 0, step: square.width) }
        .accessibilityAction(named: Text("Ausschnitt nach rechts")) { move(dx: 1, dy: 0, step: square.width) }
        .accessibilityAction(named: Text("Ausschnitt nach oben")) { move(dx: 0, dy: -1, step: square.width) }
        .accessibilityAction(named: Text("Ausschnitt nach unten")) { move(dx: 0, dy: 1, step: square.width) }
    }

    /// Ein Schritt ist ein Fünftel des Ausschnitts.
    private func move(dx: Double, dy: Double, step: Double) {
        crop = crop.moved(dx: dx * step / 5, dy: dy * step / 5, width: width, height: height)
    }
}

/// Dunkelt alles ausserhalb des Kreises ab: Das Profilbild wird rund gezeigt.
private struct CircleGuide: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            Path { path in
                path.addRect(CGRect(origin: .zero, size: proxy.size))
                path.addEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            Circle().stroke(Color.white, lineWidth: 2).frame(width: side, height: side)
        }
    }
}
