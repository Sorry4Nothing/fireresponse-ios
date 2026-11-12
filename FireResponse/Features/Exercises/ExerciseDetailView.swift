import SwiftUI

/// Detail einer Übung: Kopf, Fakten, Kontaktperson, Antworten, Anmeldungen (nur für Leitung).
struct ExerciseDetailView: View {
    @State private var model: ExerciseDetailModel
    let profile: Profile?
    let images: RemoteImages
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCalendar = false

    init(id: String, service: any ExercisesService, profile: Profile?, images: RemoteImages) {
        _model = State(initialValue: ExerciseDetailModel(id: id, service: service))
        self.profile = profile
        self.images = images
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                StateView(.loading)
            case .failed(let error):
                ScrollView {
                    StateView(error == .notFound ? .notFound : error == .network ? .offline : .error,
                              primary: error == .notFound ? { dismiss() } : { Task { await model.retry() } },
                              secondary: error == .notFound ? nil : { dismiss() })
                }
            case .loaded(let program):
                content(program)
            }
        }
        .background(Color.frSurface)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        // Stilles Nachladen nur, solange das Detail sichtbar und die App aktiv ist; im Hintergrund hält die Schleife an.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: ExerciseDetailModel.pollInterval)
                if Task.isCancelled { break }
                await model.refreshQuietly()
            }
        }
        .onChange(of: model.sentCount) {
            if let time = model.lastSentTime { AccessibilityNotification.Announcement(String(localized: "Gesendet \(time)")).post() }
        }
        .sensoryFeedback(.success, trigger: model.sentCount)
        .sensoryFeedback(.error, trigger: model.failedCount)
    }

    private func content(_ program: Program) -> some View {
        let today = model.today
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                ScreenHeader(LocalizedStringResource("\(program.title)"), subtitle: subtitle(program).map { LocalizedStringResource("\($0)") }, style: .content)
                if program.status == "abgesagt" { CancelledChip() }
                if program.status == "pruefen" { StatusChip(.review) }
                FactsCard(program: program)
                if let contact = program.contact { ContactCard(contact: contact, images: images) }
                AnswerSection(program: program, model: model, profile: profile, today: today, images: images)
                if ExerciseRules.canSeeRegistrations(program, profile: profile) {
                    NavigationLink(value: RegistrationsRoute(programId: program.id, subtitle: "\(program.title) · \(subtitle(program) ?? "")")) {
                        HStack {
                            ListRow("Anmeldungen ansehen", systemImage: "person.2")
                            Spacer(minLength: Spacing.s2)
                            Image(systemName: "chevron.right").foregroundStyle(Color.frOnSurfaceVariant).accessibilityHidden(true)
                        }
                        .padding(.horizontal, Spacing.s3)
                        .background(Color.frSurfaceContainerLow, in: RoundedRectangle(radius: Radius.md))
                        .contentShape(RoundedRectangle(radius: Radius.md))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.bottom, Spacing.s6)
            .frame(maxWidth: Sizes.contentMax, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            if program.status != "abgesagt", CalendarEvent.canAdd(program) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCalendar = true } label: { Label("In Kalender übernehmen", systemImage: "calendar.badge.plus") }
                }
            }
        }
        .sheet(isPresented: $showCalendar) { CalendarEventEditor(program: program).ignoresSafeArea() }
    }

    private func subtitle(_ program: Program) -> String? {
        ExerciseRules.startDay(program).map(ExerciseFormat.longDay)
    }
}

/// Zeit, Thema, Aufgebot und Info; Felder ohne Inhalt fallen weg.
private struct FactsCard: View {
    let program: Program

    var body: some View {
        let rows: [(symbol: String, title: LocalizedStringResource, value: String)] = [
            ("clock", "Zeit", ExerciseFormat.detailedTimeText(program)),
            ("list.bullet.clipboard", "Thema", program.topic ?? ""),
            ("backpack", "Aufgebot", program.callUp ?? ""),
            ("info.circle", "Info", program.info ?? ""),
        ].filter { !$0.2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                    Image(systemName: row.symbol).font(.system(size: 20)).foregroundStyle(Color.frAccentText).frame(width: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.footnote).foregroundStyle(Color.frOnSurfaceVariant)
                        Text(row.value).font(.body).foregroundStyle(Color.frOnSurface)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Spacing.s3)
                .accessibilityElement(children: .combine)
                if index < rows.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.frSurfaceContainerLow, in: RoundedRectangle(radius: Radius.md))
    }
}

/// Kontaktperson mit Rangabzeichen als Bild und, wenn die API eine Nummer liefert, dem Knopf «Anrufen».
private struct ContactCard: View {
    let contact: Contact
    let images: RemoteImages

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Avatar(initials: ExerciseRules.initials(contact.name), imageData: contact.imagePath.flatMap { images.data[$0] })
            VStack(alignment: .leading, spacing: 2) {
                Text(role).font(.footnote).foregroundStyle(Color.frOnSurfaceVariant)
                Text(contact.name).font(.body.weight(.semibold)).foregroundStyle(Color.frOnSurface)
            }
            if let badge = contact.badge {
                RangAbzeichen(badge.imagePath.flatMap { images.data[$0] }, width: 28, stars: badge.stars)
            }
            Spacer(minLength: Spacing.s2)
            if let dial = contact.phone.flatMap(ExerciseRules.dialString), let url = URL(string: "tel:\(dial)") {
                Link(destination: url) {
                    Image(systemName: "phone.fill").foregroundStyle(Color.frAccentText)
                        .frame(width: Sizes.touchTarget, height: Sizes.touchTarget)
                        .background(Color.frSurfaceContainer, in: .circle)
                }
                .accessibilityLabel("Anrufen, \(contact.name)")
            }
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.frSurfaceContainerLow, in: RoundedRectangle(radius: Radius.md))
        .accessibilityElement(children: .contain)
        .task(id: contact.imagePath) { await images.loadPerson(contact.imagePath) }
        .task(id: contact.badge?.imagePath) { await images.loadBadge(contact.badge) }
    }

    private var role: LocalizedStringResource {
        switch contact.role {
        case "kommandant": "Kontaktperson, Hauptleitung"
        case "stellvertretung": "Kontaktperson, stellvertretende Leitung"
        default: "Kontaktperson"
        }
    }
}

/// Ja/Nein pro teilnehmende Person und für die eigene Anmeldung als Leitung. Ohne Aktion der API gibt es keinen Knopf, nur den Stand.
private struct AnswerSection: View {
    let program: Program
    let model: ExerciseDetailModel
    let profile: Profile?
    let today: SwissDay
    let images: RemoteImages
    @State private var slow = false

    private var open: Bool { ExerciseRules.window(program, today: today) == .open }
    private var asksChildren: Bool {
        // «Kommst du?», wenn alle Personen das Konto selbst führen.
        let own = Set((profile?.participants ?? []).filter { $0.kind == "selbst" }.map(\.id))
        return !program.participants.allSatisfy { own.contains($0.id) }
    }

    var body: some View {
        if !program.participants.isEmpty || program.ownRegistration != nil {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Text(program.participants.isEmpty ? "Deine Anmeldung" : asksChildren ? "Kommen deine Kinder?" : "Kommst du?")
                    .font(.title3.bold()).foregroundStyle(Color.frOnSurface).accessibilityAddTraits(.isHeader)
                notice
                ForEach(program.participants) { person in
                    row(name: person.firstName, target: .participant(person.id), server: person.status, initials: ExerciseRules.initials(person.firstName))
                }
                if let own = program.ownRegistration {
                    let name = profile?.name ?? String(localized: "Du")
                    row(name: name, target: .leadership, server: own == "offen" ? nil : own, initials: ExerciseRules.initials(name),
                        imageData: profile?.imagePath.flatMap { images.data[$0] })
                }
                if model.saving != nil, slow {
                    Notice(.info, title: "Das dauert länger als sonst.", message: "Bitte noch einen Moment warten.")
                }
                if let error = model.error {
                    Notice(.error, title: "Antwort nicht gesendet", message: ExerciseMessage.text(for: error))
                }
            }
            .task(id: profile?.imagePath) { await images.loadPerson(profile?.imagePath) }
            .task(id: model.saving) {
                slow = false
                guard model.saving != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                slow = !Task.isCancelled
            }
        }
    }

    @ViewBuilder private var notice: some View {
        switch ExerciseRules.window(program, today: today) {
        case .open: EmptyView()
        case .opensOn(let day): Notice(.info, title: LocalizedStringResource("\(ExerciseFormat.opensOnText(day))"))
        case .closed: Notice(.info, title: "Die Anmeldung ist geschlossen.")
        }
    }

    @ViewBuilder
    private func row(name: String, target: AnswerTarget, server: String?, initials: String, imageData: Data? = nil) -> some View {
        let status = model.status(of: target, server: server)
        if open {
            ResponseControl(
                name: name, initials: initials, imageData: imageData,
                selection: status == "ja" ? .yes : status == "nein" ? .no : nil,
                detail: detail(for: target)
            ) { answer in
                Task { await model.answer(answer == .yes ? .yes : .no, for: target) }
            }
            .allowsHitTesting(model.saving == nil)
        } else {
            HStack(spacing: Spacing.s3) {
                Avatar(initials: initials, style: .calm, imageData: imageData)
                Text(name).font(.body.weight(.semibold)).foregroundStyle(Color.frOnSurface)
                Spacer(minLength: Spacing.s2)
                StatusChip(status == "ja" ? .yes : status == "nein" ? .no : .open)
            }
            .frame(minHeight: Sizes.touchTarget)
            .accessibilityElement(children: .combine)
        }
    }

    private func detail(for target: AnswerTarget) -> String? {
        if model.saving?.target == target { return String(localized: "Wird gespeichert …") }
        return model.sentAt[target].map { String(localized: "Gesendet \($0)") }
    }
}
