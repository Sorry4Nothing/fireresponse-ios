import EventKit
import EventKitUI
import SwiftUI

/// Übung als Eintrag für den Kalender des Geräts. Der Dialog des Systems läuft ausserhalb der App (iOS 17 und neuer):
/// Die App fragt keine Kalenderrechte an und liest nie Kalenderdaten.
enum CalendarEvent {
    static func canAdd(_ program: Program) -> Bool {
        program.isAllDay ? program.dayFrom != nil && program.dayTo != nil : program.start != nil && program.end != nil
    }

    static func make(_ program: Program, store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = program.title
        if program.isAllDay, let from = program.dayFrom, let until = program.dayTo {
            event.isAllDay = true
            event.startDate = ExerciseFormat.date(from)
            event.endDate = ExerciseFormat.date(until)
        } else {
            event.startDate = program.start
            event.endDate = program.end
        }
        return event
    }
}

struct CalendarEventEditor: UIViewControllerRepresentable {
    let program: Program
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = context.coordinator.store
        controller.event = CalendarEvent.make(program, store: context.coordinator.store)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let store = EKEventStore()
        let dismiss: () -> Void

        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
