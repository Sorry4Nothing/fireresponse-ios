import SwiftUI

/// Zusage pro Person: Avatar, Name, «Noch offen» bzw. Rückmeldung und zwei Kapseln Ja/Nein.
/// Ab den Accessibility-Grössen stehen die Kapseln unter dem Namen.
struct ResponseControl: View {
    enum Answer: CaseIterable {
        case yes, no
    }

    let name: String
    let initials: String
    let selection: Answer?
    /// Rückmeldung nach dem Senden, z. B. «Gesendet 12:10»; ohne Antwort steht «Noch offen».
    var detail: String?
    let onSelect: (Answer) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    init(name: String, initials: String, selection: Answer?, detail: String? = nil, onSelect: @escaping (Answer) -> Void) {
        self.name = name
        self.initials = initials
        self.selection = selection
        self.detail = detail
        self.onSelect = onSelect
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s3))
            : AnyLayout(HStackLayout(spacing: Spacing.s3))
        layout {
            HStack(spacing: Spacing.s3) {
                Avatar(initials: initials, style: .calm)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.body.weight(.semibold)).foregroundStyle(Color.frOnSurface)
                    if selection == nil {
                        Text("Noch offen").font(.footnote).foregroundStyle(Color.frOnSurfaceVariant)
                    } else if let detail {
                        Text(detail).font(.footnote).foregroundStyle(Color.frOnSurfaceVariant)
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: Spacing.s2) }
            }
            HStack(spacing: Spacing.s2) {
                ForEach(Answer.allCases, id: \.self) { answer in
                    Button { onSelect(answer) } label: { capsule(answer) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(answer.accessibilityLabel(for: name))
                        .accessibilityAddTraits(selection == answer ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func capsule(_ answer: Answer) -> some View {
        let chosen = selection == answer
        return Label { Text(answer.title) } icon: { Image(systemName: answer.symbol).fontWeight(chosen ? .heavy : .regular) }
            .font(.body.weight(.semibold))
            .foregroundStyle(chosen ? answer.foreground : Color.frOnSurface)
            .padding(.horizontal, Spacing.s4)
            .frame(minWidth: Sizes.touchTarget, minHeight: Sizes.touchTarget)
            .background(chosen ? answer.fill : .clear, in: .capsule)
            .overlay(Capsule().stroke(chosen ? answer.foreground : .frOutline, lineWidth: chosen ? 2 : 1.5))
            .contentShape(.capsule)
    }
}

extension ResponseControl.Answer {
    fileprivate var title: LocalizedStringResource { self == .yes ? "Ja" : "Nein" }
    fileprivate var symbol: String { self == .yes ? "checkmark" : "xmark" }
    fileprivate var fill: Color { self == .yes ? .frSuccessContainer : .frErrorContainer }
    fileprivate var foreground: Color { self == .yes ? .frOnSuccessContainer : .frOnErrorContainer }

    /// Beginnt mit dem sichtbaren Wort, danach die Person.
    fileprivate func accessibilityLabel(for name: String) -> Text {
        Text(self == .yes ? "Ja für \(name)" : "Nein für \(name)")
    }
}

#if DEBUG
private struct ResponseControlDemo: View {
    var body: some View {
        VStack(spacing: Spacing.s4) {
            ResponseControl(name: "Anna", initials: "A", selection: nil) { _ in }
            ResponseControl(name: "Ben", initials: "B", selection: .yes, detail: "Gesendet 12:10") { _ in }
            ResponseControl(name: "Cleo", initials: "C", selection: .no) { _ in }
        }
    }
}

#Preview("Nacht, AX5") { ResponseControlDemo().frPreview(.dark) }
#Preview("Tag, normal") { ResponseControlDemo().frPreview(.light, size: .large) }
#endif
