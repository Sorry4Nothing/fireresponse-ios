import SwiftUI

/// Abschnitt «Leiter-Plätze» im Detail (Issue #66): Stand der Plätze, Leitende mit Zusage mit Profilbild, freie Plätze als Platzhalter
/// und die Warteliste. Nur für Kommando und Leitung: Der Schlüssel `leitungPlaetze` fehlt für alle anderen, dann gibt es den Abschnitt nicht.
struct LeaderSlotsSection: View {
    let program: Program
    let model: ExerciseDetailModel
    let images: RemoteImages

    var body: some View {
        if let slots = model.leaderSlots ?? program.leaderSlots {
            let own = model.status(of: .leadership, server: program.ownRegistration)
            let line = LeaderSlotsText.line(slots, own: own)
            let confirmed = model.leaders.filter { $0.status == "ja" }
            let waiting = model.leaders.filter { $0.status == "warteliste" }.sorted { ($0.position ?? .max) < ($1.position ?? .max) }
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Text("Leiter-Plätze").font(.title3.bold()).foregroundStyle(Color.frOnSurface).accessibilityAddTraits(.isHeader)
                Label(line.text, systemImage: line.symbol).font(.body.weight(.semibold)).foregroundStyle(Color.frOnSurface)
                    .accessibilityLabel(line.spoken)
                ForEach(confirmed) { leader in
                    HStack(spacing: Spacing.s3) {
                        Avatar(initials: ExerciseRules.initials(leader.name), style: .calm, imageData: leader.imagePath.flatMap { images.data[$0] })
                        Text(verbatim: leader.name).font(.body).foregroundStyle(Color.frOnSurface)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: Sizes.touchTarget)
                    .accessibilityElement(children: .combine)
                }
                ForEach(0..<max(0, slots.free), id: \.self) { _ in
                    HStack(spacing: Spacing.s3) {
                        Image(systemName: "person.crop.circle.dashed").font(.system(size: 28)).foregroundStyle(Color.frOnSurfaceVariant)
                            .frame(width: Sizes.avatar, height: Sizes.avatar).accessibilityHidden(true)
                        Text("Platz frei").font(.body).foregroundStyle(Color.frOnSurfaceVariant)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: Sizes.touchTarget)
                    .accessibilityElement(children: .combine)
                }
                if let waitingText = LeaderSlotsText.waitingText(slots.waiting) {
                    Text(waitingText).font(.subheadline).foregroundStyle(Color.frOnSurfaceVariant)
                    ForEach(waiting) { leader in
                        HStack(spacing: Spacing.s3) {
                            Avatar(initials: ExerciseRules.initials(leader.name), style: .calm, imageData: leader.imagePath.flatMap { images.data[$0] })
                            Text(verbatim: leader.name).font(.body).foregroundStyle(Color.frOnSurface)
                            Spacer(minLength: 0)
                            if let position = leader.position { Text("Platz \(position)").font(.footnote).foregroundStyle(Color.frOnSurfaceVariant) }
                        }
                        .frame(minHeight: Sizes.touchTarget)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(Spacing.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.frSurfaceContainerLow, in: RoundedRectangle(radius: Radius.md))
            .task(id: model.leaders.map(\.id)) {
                for leader in model.leaders { await images.loadPerson(leader.imagePath) }
            }
        }
    }
}

/// Die eigene Zusage bei Terminen mit Plätzen für Leitende: bei «Voll» «Auf die Warteliste setzen», auf der Warteliste «Von der Warteliste nehmen»,
/// beim Absagen mit Platz eine Bestätigung. Sonst die gewohnte Wahl Ja/Nein.
struct LeadershipControl: View {
    let program: Program
    let model: ExerciseDetailModel
    let name: String
    let imageData: Data?
    let detail: String?
    @State private var confirmDecline = false

    private var own: String? { model.status(of: .leadership, server: program.ownRegistration == "offen" ? nil : program.ownRegistration) }
    private var slots: LeaderSlots? { model.leaderSlots ?? program.leaderSlots }
    private var savingOwn: Bool { model.saving?.target == .leadership }

    var body: some View {
        Group {
            if own == "warteliste" {
                waitlisted
            } else if own != "ja", slots?.isFull == true {
                joinWaitlist
            } else {
                ResponseControl(
                    name: name, initials: ExerciseRules.initials(name), imageData: imageData,
                    selection: own == "ja" ? .yes : own == "nein" ? .no : nil, detail: detail
                ) { answer in
                    if answer == .no, own == "ja", slots != nil { confirmDecline = true } else {
                        Task { await model.answer(answer == .yes ? .yes : .no, for: .leadership) }
                    }
                }
                .allowsHitTesting(model.saving == nil)
            }
        }
        .alert("Absagen?", isPresented: $confirmDecline) {
            Button("Abbrechen", role: .cancel) {}
            Button("Absagen", role: .destructive) { Task { await model.answer(.no, for: .leadership) } }
        } message: {
            Text((slots?.waiting ?? 0) > 0 ? "Dein Platz geht an die nächste Person auf der Warteliste." : "Dein Platz wird frei.")
        }
    }

    private var waitlisted: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(spacing: Spacing.s3) {
                Avatar(initials: ExerciseRules.initials(name), style: .calm, imageData: imageData)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name).font(.body.weight(.semibold)).foregroundStyle(Color.frOnSurface)
                    if let slots { Text(verbatim: LeaderSlotsText.line(slots, own: "warteliste").text).font(.footnote).foregroundStyle(Color.frOnSurfaceVariant) }
                }
            }
            .accessibilityElement(children: .combine)
            FRButton(savingOwn ? "Wird entfernt …" : "Von der Warteliste nehmen", kind: .outline) {
                Task { await model.answer(.no, for: .leadership) }
            }
            .disabled(model.saving != nil)
        }
    }

    private var joinWaitlist: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(spacing: Spacing.s3) {
                Avatar(initials: ExerciseRules.initials(name), style: .calm, imageData: imageData)
                Text(verbatim: name).font(.body.weight(.semibold)).foregroundStyle(Color.frOnSurface)
            }
            .accessibilityElement(children: .combine)
            FRButton(savingOwn ? "Wird eingetragen …" : "Auf die Warteliste setzen") {
                Task { await model.answer(.yes, for: .leadership) }
            }
            .disabled(model.saving != nil)
        }
    }
}
