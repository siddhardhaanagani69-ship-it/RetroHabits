import Foundation
import Combine
import UserNotifications

/// Classes, shifts and other weekly commitments, saved on the phone. Each one
/// gets a repeating weekly reminder per day, so reminders keep firing even if
/// the app isn't opened.
@MainActor
final class RoutineStore: ObservableObject {
    static let shared = RoutineStore()

    @Published private(set) var routines: [Routine] = [] {
        didSet {
            save()
            AgendaStore.shared.mergeRoutines()
        }
    }

    private let fileURL = URL.documentsDirectory.appending(path: "routines.json")

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Routine].self, from: data) {
            // Set the wrapper directly: assigning `routines` here would run didSet
            // (@Published fires it even in init), which calls back into
            // AgendaStore.shared while AgendaStore may still be initializing.
            _routines = Published(initialValue: saved)
        }
    }

    func add(_ routine: Routine) {
        routines.append(routine)
        scheduleReminders(for: routine)
    }

    func update(_ routine: Routine) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        routines[index] = routine
        scheduleReminders(for: routine)
    }

    func delete(_ routine: Routine) {
        routines.removeAll { $0.id == routine.id }
        cancelReminders(for: routine)
    }

    /// Routines on a given day, earliest first.
    func routines(on day: Date) -> [Routine] {
        let weekday = Calendar.current.component(.weekday, from: day)
        return routines
            .filter { $0.weekdays.contains(weekday) }
            .sorted { ($0.startHour, $0.startMinute) < ($1.startHour, $1.startMinute) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(routines) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Reminders

    private func scheduleReminders(for routine: Routine) {
        cancelReminders(for: routine)
        guard let lead = routine.remindMinutesBefore else { return }
        let center = UNUserNotificationCenter.current()
        let startText = Self.time(routine)

        for weekday in routine.weekdays {
            // The reminder can fall on the previous day (a 12:10 AM start, 30 min lead).
            var minutes = routine.startHour * 60 + routine.startMinute - lead
            var day = weekday
            if minutes < 0 {
                minutes += 24 * 60
                day = weekday == 1 ? 7 : weekday - 1
            }
            let components = DateComponents(hour: minutes / 60, minute: minutes % 60, weekday: day)

            let content = UNMutableNotificationContent()
            content.title = lead == 0 ? "\(routine.name) is starting" : "\(routine.name) in \(lead) min"
            content.body = [startText, routine.location].compactMap { $0 }.joined(separator: " · ")
            content.sound = .default
            center.add(UNNotificationRequest(
                identifier: "routine-\(routine.id.uuidString)-\(weekday)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            ))
        }
    }

    private func cancelReminders(for routine: Routine) {
        let ids = (1...7).map { "routine-\(routine.id.uuidString)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// "10:00 AM – 11:15 AM" in the user's locale.
    static func time(_ routine: Routine) -> String {
        guard let start = routine.start(on: .now) else { return "" }
        let end = start.addingTimeInterval(TimeInterval(routine.durationMinutes * 60))
        return (start..<end).formatted(.interval.hour().minute())
    }
}
