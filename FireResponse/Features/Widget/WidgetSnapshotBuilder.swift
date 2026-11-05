import Foundation
import WidgetKit

nonisolated enum WidgetRules {
    /// Die nächsten Übungen: nicht abgesagt, nicht vorbei, nach Beginn geordnet. Ohne lesbare Zeit zählt eine Übung nicht.
    static func upcoming(_ programs: [Program], now: Date, count: Int = WidgetSnapshot.storedRows) -> [Program] {
        programs
            .compactMap { program -> (program: Program, start: Date, end: Date)? in
                guard program.status != "abgesagt", let times = times(program) else { return nil }
                return (program, times.start, times.end)
            }
            .filter { $0.end >= now }
            .sorted { $0.start < $1.start }
            .prefix(count)
            .map(\.program)
    }

    /// Beginn und Ende; ganztägig von Mitternacht des ersten bis Mitternacht nach dem letzten Tag.
    static func times(_ program: Program) -> (start: Date, end: Date)? {
        if program.isAllDay {
            guard let from = program.dayFrom, let until = program.dayTo else { return nil }
            // shortcut: Mittag ± 12 Stunden, an Tagen der Zeitumstellung eine Stunde daneben; nur für das Ausblenden.
            return (ExerciseFormat.date(from).addingTimeInterval(-12 * 3600), ExerciseFormat.date(until).addingTimeInterval(12 * 3600))
        }
        guard let start = program.start, let end = program.end else { return nil }
        return (start, end)
    }

    static func stand(_ status: String?) -> WidgetSnapshot.Stand {
        switch status {
        case "ja": .yes
        case "nein": .no
        default: .open
        }
    }
}

extension WidgetSnapshot {
    /// Die Zeilen des Widgets aus der Liste der API. Wie auf Android: vor dem Anmeldefenster «ab 5.12.» statt der Personen.
    static func make(from programs: [Program], now: Date = .now) -> WidgetSnapshot {
        let today = SwissDay(date: now)
        let rows = WidgetRules.upcoming(programs, now: now).compactMap { program -> Row? in
            guard let times = WidgetRules.times(program) else { return nil }
            let day = ExerciseRules.startDay(program) ?? today
            let startText = program.isAllDay ? String(localized: "Ganztägig") : program.start.map(ExerciseFormat.time) ?? ""

            var people: [Person] = []
            var count: String?
            var opensText: String?
            if case .opensOn(let opens) = ExerciseRules.window(program, today: today) {
                count = String(localized: "ab \(ExerciseFormat.numeric(opens))")
                opensText = ExerciseFormat.opensOnText(opens)
            } else if program.isRegistrable {
                people = program.participants.map { Person(name: $0.firstName, stand: WidgetRules.stand($0.status)) }
                    + (program.ownRegistration.map { [Person(name: String(localized: "Du"), stand: WidgetRules.stand($0))] } ?? [])
                if !people.isEmpty {
                    count = String(localized: "\(people.filter { $0.stand != .open }.count) von \(people.count)")
                }
            }

            let spoken = [
                ExerciseFormat.longDay(day),
                ExerciseFormat.spokenTime(program),
                program.title,
                String(localized: "Einheit \(program.unit.name)"),
                opensText,
                people.isEmpty ? nil : people.map { "\($0.name): \(Self.spoken($0.stand))" }.joined(separator: ", "),
            ].compactMap { $0 }.joined(separator: ", ") + ". " + String(localized: "Öffnet die Übung")

            return Row(
                id: program.id,
                title: program.title,
                unitType: program.unit.type.uppercased(),
                when: "\(ExerciseFormat.shortDay(day)) · \(startText)",
                count: count,
                people: people,
                spoken: spoken,
                endsAt: times.end
            )
        }
        return WidgetSnapshot(rows: rows)
    }

    private static func spoken(_ stand: Stand) -> String {
        switch stand {
        case .yes: String(localized: "kommt")
        case .no: String(localized: "kommt nicht")
        case .open: String(localized: "offen")
        }
    }
}

/// Schreibt den Stand fürs Widget und lässt es neu zeichnen.
@MainActor
enum WidgetSync {
    static func update(programs: [Program], store: WidgetSnapshotStore? = .appGroup) {
        guard let store else { return }
        store.write(.make(from: programs))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Beim Abmelden: Namen und Übungen der vorigen Person dürfen nicht stehen bleiben.
    static func clear(store: WidgetSnapshotStore? = .appGroup) {
        store?.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
