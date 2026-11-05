import SwiftUI

/// Datenschutzerklärung in einfacher Sprache; der Text kommt von der API (`GET /datenschutz`, öffentlich).
/// Als Sheet von Willkommen (mit «Fertig») und aus dem Profil nutzbar.
struct PrivacyView: View {
    let api: FireResponseAPI
    var unitName: String?
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState = .loading

    private enum LoadState { case loading, loaded(Privacy), failed(FormError) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                ScreenHeader("Datenschutz", subtitle: unitName.map { LocalizedStringResource(stringLiteral: $0) })
                switch state {
                case .loading:
                    ProgressView("Datenschutz wird geladen").frame(maxWidth: .infinity).padding(.top, Spacing.s8)
                case .failed(let error):
                    Notice(.error, title: error.title, message: error.message)
                    FRButton("Nochmals versuchen", systemImage: "arrow.clockwise") { Task { await load() } }
                case .loaded(let privacy):
                    ForEach(privacy.sections.indices, id: \.self) { index in
                        section(privacy.sections[index])
                    }
                    Text("Fassung \(privacy.version)").font(.footnote).foregroundStyle(Color.frOnSurfaceVariant)
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: Sizes.contentMax, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.frSurface)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        .task { await load() }
    }

    private func section(_ section: PrivacySection) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(section.title).font(.headline).foregroundStyle(Color.frOnSurface).accessibilityAddTraits(.isHeader)
            ForEach(Array(section.text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph).font(.body).foregroundStyle(Color.frOnSurface)
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.frSurfaceContainerLow, in: RoundedRectangle(radius: Radius.md))
        .overlay(RoundedRectangle(radius: Radius.md).stroke(Color.frOutlineVariant, lineWidth: 1))
    }

    private func load() async {
        state = .loading
        switch await api.privacy() {
        case .ok(let privacy): state = .loaded(privacy)
        case .failure(let error, _, let retry): state = .failed(.from(error, retryAfterSeconds: retry))
        }
    }
}
