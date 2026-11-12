import SwiftUI

/// Ziele im Stapel der Übungen.
private struct DetailRoute: Hashable { let id: String }
struct RegistrationsRoute: Hashable {
    let programId: String
    let subtitle: String
}

/// Tab «Übungen»: Liste als Zeitleiste, Detail, Anmeldungen der Einheit.
struct ExercisesRootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ExercisesStack(service: app.api, profile: app.profile)
    }
}

struct ExercisesStack: View {
    let service: any ExercisesService
    let profile: Profile?
    @State private var list: ExerciseListModel
    @State private var images: RemoteImages
    @State private var path = NavigationPath()
    private let router: PushRouter

    init(service: any ExercisesService, profile: Profile?, router: PushRouter = PushCenter.shared.router) {
        self.router = router
        self.service = service
        self.profile = profile
        _list = State(initialValue: ExerciseListModel(service: service, onLoaded: { WidgetSync.update(programs: $0) }))
        _images = State(initialValue: RemoteImages(service: service))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ExerciseListView(model: list, images: images)
                .navigationTitle("Übungen")
                .navigationDestination(for: DetailRoute.self) { route in
                    ExerciseDetailView(id: route.id, service: service, profile: profile, images: images)
                }
                .navigationDestination(for: RegistrationsRoute.self) { route in
                    RegistrationsView(route: route, service: service, images: images)
                }
                .onChange(of: router.pending, initial: true) {
                    if case .appointment(let id) = router.consume() { path.append(DetailRoute(id: id)) }
                }
        }
    }
}

struct ExerciseListView: View {
    let model: ExerciseListModel
    let images: RemoteImages

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                StateView(.loading)
            case .failed(let error):
                ScrollView { StateView(error.stateKind, primary: { Task { await model.retry() } }) }
            case .loaded(let days) where days.isEmpty:
                ScrollView { StateView(.empty, primary: { Task { await model.load() } }) }
            case .loaded(let days):
                ScrollView {
                    // Der Abstand zwischen den Tagen liegt in den Zeilen selbst, damit die Linie links nirgends abreisst.
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if let error = model.refreshError {
                            Notice(.error, title: "Aktualisieren hat nicht geklappt", message: ExerciseMessage.text(for: error))
                                .padding(.bottom, Spacing.s5)
                        }
                        let sections = ExerciseRules.groupByMonth(days)
                        ForEach(sections) { section in
                            if let heading = section.heading { MonthHeading(text: heading) }
                            ForEach(section.days) { day in
                                DayRow(day: day, today: model.today, images: images, isLast: day.id == sections.last?.days.last?.id)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.s4)
                    .padding(.bottom, Spacing.s4)
                    .frame(maxWidth: Sizes.contentMax, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color.frSurface)
        .refreshable { await model.load() }
        .task { await model.load() }
    }
}

extension ApiError {
    /// Zustandsbild für einen Ladefehler.
    fileprivate var stateKind: StateView.Kind {
        switch self {
        case .network: .offline
        case .notFound: .notFound
        case .forbidden: .noAccess
        case .notSignedIn: .sessionExpired
        default: .error
        }
    }
}

/// Ein Tag der Zeitleiste: links das Datum an einer Linie, rechts die Karten. Ab AX1 steht das Datum über den Karten.
/// Monats-Überschrift der Zeitleiste; die Linie links läuft an ihr vorbei.
private struct MonthHeading: View {
    let text: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s2) {
            if !typeSize.isAccessibilitySize {
                Capsule().fill(Color.frOutlineVariant).frame(width: 2).frame(width: 48).frame(maxHeight: .infinity).accessibilityHidden(true)
            }
            Text(text).font(.frMonth).foregroundStyle(Color.frOnSurface).accessibilityAddTraits(.isHeader)
                .padding(.bottom, Spacing.s3)
            Spacer(minLength: 0)
        }
    }
}

private struct DayRow: View {
    let day: ProgramDay
    let today: SwissDay
    let images: RemoteImages
    /// Das letzte Datum beendet die Linie; sonst reicht sie bis zum nächsten.
    let isLast: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                if let date = day.day {
                    Text(ExerciseFormat.longDay(date)).font(.title3.bold()).foregroundStyle(Color.frAccentText)
                        .accessibilityAddTraits(.isHeader)
                }
                cards
            }
            .padding(.bottom, isLast ? 0 : Spacing.s5)
        } else {
            HStack(alignment: .top, spacing: Spacing.s2) {
                if let date = day.day {
                    VStack(spacing: Spacing.s1) {
                        Text(ExerciseFormat.weekdayShort(date)).font(.footnote.weight(.bold)).foregroundStyle(Color.frAccentText)
                        Text(String(date.day)).font(.frDay).foregroundStyle(Color.frOnSurface)
                        Capsule().fill(Color.frOutlineVariant).frame(width: 2).frame(maxHeight: .infinity)
                    }
                    .frame(width: 48)
                    .accessibilityHidden(true)
                } else {
                    Color.clear.frame(width: 48, height: 1)
                }
                cards.padding(.bottom, isLast ? 0 : Spacing.s5)
            }
        }
    }

    private var cards: some View {
        VStack(spacing: Spacing.s2) {
            ForEach(day.programs) { ExerciseCard(program: $0, today: today, images: images) }
        }
    }
}

/// Karte einer Übung: Zeit, Titel, Stand je Person. Ganze Karte ein Ziel, VoiceOver liest einen vollständigen Satz.
/// Der Rang steht nicht auf der Karte: Übungen gelten für die ganze Gruppe.
private struct ExerciseCard: View {
    let program: Program
    let today: SwissDay
    let images: RemoteImages
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationLink(value: DetailRoute(id: program.id)) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(ExerciseFormat.timeText(program)).font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(Color.frAccentText)
                    .padding(.trailing, UnitMark.reservedWidth)
                Text(program.title).font(.frCardTitle).foregroundStyle(Color.frOnSurface)
                    .padding(.trailing, UnitMark.reservedWidth)
                if program.status == "abgesagt" { CancelledChip() }
                if program.status == "pruefen" { StatusChip(.review) }
                ForEach(Array(ExerciseFormat.statusSentences(program).enumerated()), id: \.offset) { _, line in
                    Label(line.text, systemImage: line.symbol).font(.footnote.weight(.semibold)).foregroundStyle(line.kind.color)
                }
                if case .opensOn(let day) = ExerciseRules.window(program, today: today) {
                    Label(ExerciseFormat.opensOnText(day), systemImage: "clock").font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.frOnSurfaceVariant)
                }
            }
            .padding(typeSize.isAccessibilitySize ? Spacing.s4 : Spacing.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Sizes.touchTarget)
            .overlay(alignment: .topTrailing) {
                let key = RemoteImages.logoKey(program.unit.id)
                UnitMark(data: images.data[key], type: program.unit.type, settled: images.settledLogos.contains(key))
                    .padding(typeSize.isAccessibilitySize ? Spacing.s4 : Spacing.s3)
            }
            .background(Color.frSurfaceContainerLow, in: RoundedRectangle(radius: Radius.md))
            .contentShape(RoundedRectangle(radius: Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ExerciseFormat.cardSentence(program, today: today))
        .accessibilityAddTraits(.isButton)
        .task(id: program.unit.id) { await images.loadLogo(program.unit) }
    }
}

extension ExerciseFormat.StatusKind {
    var color: Color {
        switch self {
        case .yes: .frOnSuccessContainer
        case .no: .frOnErrorContainer
        case .open: .frOnSurfaceVariant
        }
    }
}

/// «Abgesagt» mit Symbol und Wort (der StatusChip kennt nur Ja/Nein).
struct CancelledChip: View {
    var body: some View {
        Label("Abgesagt", systemImage: "xmark.circle")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.frOnErrorContainer)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(Color.frErrorContainer, in: .capsule)
    }
}
