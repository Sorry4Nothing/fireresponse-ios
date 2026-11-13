import SwiftUI

/// Anmeldungen der Einheit für Leitung und Kommando, nur lesend: Balken, Umschalter Kinder/Leitende, eine Zeile pro Person.
struct RegistrationsView: View {
    let route: RegistrationsRoute
    let images: RemoteImages
    @State private var model: RegistrationsModel
    @State private var showLeaders = false
    @Environment(\.dynamicTypeSize) private var typeSize

    init(route: RegistrationsRoute, service: any ExercisesService, images: RemoteImages) {
        self.route = route
        self.images = images
        _model = State(initialValue: RegistrationsModel(programId: route.programId, service: service))
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                StateView(.loading)
            case .failed(let error):
                ScrollView {
                    StateView(error == .forbidden ? .noAccess : error == .network ? .offline : .error,
                              primary: { Task { await model.retry() } })
                }
            case .loaded(let value):
                ScrollView { content(value).padding(.horizontal, Spacing.s4).padding(.bottom, Spacing.s6) }
            }
        }
        .background(Color.frSurface)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    private func content(_ value: Participations) -> some View {
        let counts = showLeaders ? value.counts.leaders : value.counts.participants
        let rows = showLeaders
            ? ExerciseRules.sortedByStatus(value.leaders, status: \.status).map { Row(id: $0.id, name: $0.name, role: roleText($0.role), imagePath: $0.imagePath, badge: $0.badge, status: $0.status) }
            : ExerciseRules.sortedByStatus(value.participants, status: \.status)
                .map { Row(id: $0.id, name: "\($0.firstName) \($0.lastName)", role: nil, imagePath: nil, badge: $0.badge, status: $0.status) }
        return VStack(alignment: .leading, spacing: Spacing.s4) {
            ScreenHeader("Anmeldungen", subtitle: LocalizedStringResource("\(route.subtitle)"))
            Summary(counts: counts)
            HStack(spacing: Spacing.s2) {
                tab("Kinder · \(value.counts.participants.total)", selected: !showLeaders) { showLeaders = false }
                tab("Leitende · \(value.counts.leaders.total)", selected: showLeaders) { showLeaders = true }
            }
            if rows.isEmpty {
                Notice(.info, title: showLeaders ? "Es gibt keine Leitenden in dieser Einheit." : "Es gibt keine Kinder in dieser Einheit.")
            }
            ForEach(rows) { PersonRow(row: $0, images: images) }
            Text("Sortiert: offen zuerst, dann Ja, dann Nein.").font(.footnote).foregroundStyle(Color.frOnSurfaceVariant)
        }
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body.weight(.semibold))
                .foregroundStyle(selected ? Color.frOnSecondaryContainer : .frOnSurface)
                .padding(.horizontal, Spacing.s4)
                .frame(minHeight: Sizes.touchTarget)
                .background(selected ? Color.frSecondaryContainer : .clear, in: .capsule)
                .overlay(Capsule().stroke(selected ? Color.frOnSecondaryContainer : .frOutline, lineWidth: selected ? 2 : 1.5))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func roleText(_ role: String) -> LocalizedStringResource? {
        switch role {
        case "kommandant": "Hauptleitung"
        case "stellvertretung": "Stellvertretende Leitung"
        case "leitung": "Leitung"
        default: nil
        }
    }

    fileprivate struct Row: Identifiable {
        let id: String
        let name: String
        let role: LocalizedStringResource?
        let imagePath: String?
        let badge: Badge?
        let status: String
    }
}

/// Balken Ja/Nein/Offen mit Legende aus Zahl, Symbol und Wort; für VoiceOver ein Satz.
private struct Summary: View {
    let counts: ParticipationCount

    private var total: Int { counts.total }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    segment(counts.yes, Color.frOnSuccessContainer, proxy.size.width)
                    segment(counts.no, Color.frOnErrorContainer, proxy.size.width)
                    segment(counts.open, Color.frOutlineVariant, proxy.size.width)
                }
            }
            .frame(height: 14)
            .background(total == 0 ? Color.frSurfaceContainerHigh : .clear, in: .capsule)
            HStack(spacing: Spacing.s4) {
                Label("\(counts.yes) Ja", systemImage: "checkmark").foregroundStyle(Color.frOnSuccessContainer)
                if counts.waitlist > 0 { Label("\(counts.waitlist) Warteliste", systemImage: "clock").foregroundStyle(Color.frOnSurfaceVariant) }
                Label("\(counts.no) Nein", systemImage: "xmark").foregroundStyle(Color.frOnErrorContainer)
                Label("\(counts.open) offen", systemImage: "questionmark.circle").foregroundStyle(Color.frOnSurfaceVariant)
            }
            .font(.footnote.weight(.bold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(counts.waitlist > 0
            ? "\(counts.yes) Ja, \(counts.waitlist) Warteliste, \(counts.no) Nein, \(counts.open) offen von \(total)"
            : "\(counts.yes) Ja, \(counts.no) Nein, \(counts.open) offen von \(total)")
    }

    @ViewBuilder private func segment(_ count: Int, _ color: Color, _ width: CGFloat) -> some View {
        if count > 0 { Capsule().fill(color).frame(width: max(6, (width - 6) * CGFloat(count) / CGFloat(total))) }
    }
}

private struct PersonRow: View {
    let row: RegistrationsView.Row
    let images: RemoteImages
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.s2))
            : AnyLayout(HStackLayout(spacing: Spacing.s3))
        layout {
            HStack(spacing: Spacing.s3) {
                Avatar(initials: ExerciseRules.initials(row.name), style: .calm, imageData: row.imagePath.flatMap { images.data[$0] })
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(.body.weight(.semibold)).foregroundStyle(Color.frOnSurface)
                    if let role = row.role { Text(role).font(.footnote).foregroundStyle(Color.frOnSurfaceVariant) }
                }
                if let badge = row.badge { RangAbzeichen(badge.imagePath.flatMap { images.data[$0] }, width: 24, stars: badge.stars) }
                if !typeSize.isAccessibilitySize { Spacer(minLength: Spacing.s2) }
            }
            StatusChip(row.status == "ja" ? .yes : row.status == "nein" ? .no : row.status == "warteliste" ? .waitlist : .open)
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, minHeight: Sizes.touchTarget, alignment: .leading)
        .background(Color.frSurfaceContainerLow, in: RoundedRectangle(radius: Radius.md))
        .accessibilityElement(children: .combine)
        .task(id: row.imagePath) { await images.loadPerson(row.imagePath) }
        .task(id: row.badge?.imagePath) { await images.loadBadge(row.badge) }
    }
}
