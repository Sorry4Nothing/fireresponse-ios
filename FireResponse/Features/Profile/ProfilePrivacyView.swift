import SwiftUI

/// Datenschutzerklärung aus `GET /datenschutz` (der Text kommt vom Server, damit er ohne App-Update ändern kann).
struct ProfilePrivacyView: View {
    var unitName: String?
    @Environment(AppModel.self) private var model
    @State private var privacy: Privacy?
    @State private var failed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                ScreenHeader("Datenschutz", subtitle: unitName.map { LocalizedStringResource("\($0)") })
                if let privacy {
                    ForEach(privacy.sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: Spacing.s2) {
                            Text(verbatim: section.title).font(.headline).foregroundStyle(Color.frOnSurface)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.text.components(separatedBy: "\n\n"), id: \.self) { paragraph in
                                Text(verbatim: paragraph).font(.body).foregroundStyle(Color.frOnSurface)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.s4)
                        .background(Color.frSurfaceContainerLow, in: RoundedRectangle(radius: Radius.md))
                    }
                    Text("Fassung \(privacy.version)").font(.footnote).foregroundStyle(Color.frOnSurfaceVariant)
                } else if failed {
                    StateView(.error, primary: { Task { await load() } })
                } else {
                    ProgressView().controlSize(.large).frame(maxWidth: .infinity)
                        .accessibilityLabel(Text("Datenschutz wird geladen"))
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: Sizes.contentMax)
            .frame(maxWidth: .infinity)
        }
        .background(Color.frSurface)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        failed = false
        switch await model.api.privacy() {
        case .ok(let value): privacy = value
        case .failure: failed = true
        }
    }
}
