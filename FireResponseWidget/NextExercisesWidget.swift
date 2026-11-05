import SwiftUI
import WidgetKit

/// Widget «Nächste Übungen» (mittel): die nächsten zwei Übungen mit dem Stand der Antworten, nur zum Ansehen.
/// Es liest, was die App zuletzt geschrieben hat (`WidgetSnapshotStore`); ein Tipp öffnet die App bei der Übung.
struct NextExercisesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextExercises", provider: ExercisesProvider()) { entry in
            NextExercisesView(entry: entry)
                .containerBackground(Color.frSurfaceContainerLow, for: .widget)
        }
        .configurationDisplayName("Nächste Übungen")
        .description("Die nächsten zwei Übungen mit dem Stand deiner Antwort. Antworten kannst du in der App.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

struct ExercisesEntry: TimelineEntry {
    enum Content: Equatable {
        /// Nichts gespeichert: nie angemeldet oder abgemeldet.
        case signedOut
        case rows([WidgetSnapshot.Row])
    }

    let date: Date
    let content: Content
}

struct ExercisesProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExercisesEntry {
        ExercisesEntry(date: .now, content: .rows(Self.sample))
    }

    func getSnapshot(in context: Context, completion: @escaping (ExercisesEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Self.entries(now: .now, snapshot: WidgetSnapshotStore.appGroup?.read())[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExercisesEntry>) -> Void) {
        completion(Timeline(entries: Self.entries(now: .now, snapshot: WidgetSnapshotStore.appGroup?.read()), policy: .atEnd))
    }

    /// Ein Eintrag jetzt und je einer, wenn eine Übung endet: Dann rückt die nächste nach, auch ohne dass die App läuft.
    static func entries(now: Date, snapshot: WidgetSnapshot?) -> [ExercisesEntry] {
        guard let snapshot else { return [ExercisesEntry(date: now, content: .signedOut)] }
        let dates = [now] + snapshot.rows.map(\.endsAt).filter { $0 > now }.sorted()
        return dates.map { date in
            ExercisesEntry(date: date, content: .rows(Array(snapshot.rows.filter { $0.endsAt > date }.prefix(WidgetSnapshot.visibleRows))))
        }
    }

    /// Für die Galerie; erfundene Vornamen, nie echte Daten.
    static let sample = [
        WidgetSnapshot.Row(
            id: "1", title: "Schlussübung / Verabschiedungen", unitType: "KF", when: "MI 18.11. · 19:00", count: "2 von 2",
            people: [.init(name: "Lena", stand: .yes), .init(name: "Noah", stand: .yes)], spoken: "", endsAt: .distantFuture
        ),
        WidgetSnapshot.Row(
            id: "2", title: "Geländespiel im Wald", unitType: "JF", when: "SA 21.11. · 13:30", count: "1 von 2",
            people: [.init(name: "Lena", stand: .no), .init(name: "Noah", stand: .open)], spoken: "", endsAt: .distantFuture
        ),
    ]
}

#Preview("Widget", as: .systemMedium) {
    NextExercisesWidget()
} timeline: {
    ExercisesEntry(date: .now, content: .rows(ExercisesProvider.sample))
    ExercisesEntry(date: .now, content: .rows([ExercisesProvider.sample[0]]))
    ExercisesEntry(date: .now, content: .signedOut)
}
