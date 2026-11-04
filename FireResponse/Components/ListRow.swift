import SwiftUI

/// Inhalt einer Zeile in einer inset-grouped Liste: Symbol, Text und optional ein Wert rechts.
/// Als Label von `Toggle` (Tint `.frSwitchOn`), `NavigationLink` oder `Button` verwendbar.
struct ListRow: View {
    let title: LocalizedStringResource
    let systemImage: String
    var value: LocalizedStringResource?
    var role: ButtonRole?

    init(_ title: LocalizedStringResource, systemImage: String, value: LocalizedStringResource? = nil, role: ButtonRole? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.role = role
    }

    var body: some View {
        Group {
            if let value {
                LabeledContent {
                    Text(value).foregroundStyle(Color.frOnSurfaceVariant)
                } label: { label }
            } else {
                label
            }
        }
        .font(.body)
        .frame(minHeight: Sizes.touchTarget, alignment: .leading)
    }

    private var label: some View {
        Label {
            Text(title).foregroundStyle(role == .destructive ? Color.frPrimaryText : .frOnSurface)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(role == .destructive ? Color.frPrimaryText : .frAccent)
        }
    }
}

#if DEBUG
private struct ListRowDemo: View {
    @State private var faceID = true
    var body: some View {
        List {
            Section("App") {
                ListRow("Benachrichtigungen", systemImage: "bell", value: "Kommt bald")
                Toggle(isOn: $faceID) { ListRow("Mit Face ID entsperren", systemImage: "faceid") }.tint(.frSwitchOn)
                NavigationLink {} label: { ListRow("Datenschutz", systemImage: "hand.raised") }
            }
            .listRowBackground(Color.frSurfaceContainerLow)
            Section("Konto") {
                Button(role: .destructive) {} label: {
                    ListRow("Abmelden", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive)
                }
            }
            .listRowBackground(Color.frSurfaceContainerLow)
        }
        .scrollContentBackground(.hidden)
    }
}

#Preview("Nacht, AX5") { NavigationStack { ListRowDemo() }.frPreview(.dark) }
#Preview("Tag, normal") { NavigationStack { ListRowDemo() }.frPreview(.light, size: .large) }
#endif
