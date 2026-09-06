import Foundation
import WidgetKit

/// What the home screen widget shows. Written by the app into a shared
/// App Group container and read by the widget extension.
struct WidgetSnapshot: Codable {
    struct HabitLine: Codable, Identifiable {
        var id: String
        var name: String
        var icon: String
        var done: Bool
        var streak: Int
    }

    struct EventLine: Codable, Identifiable {
        var id: String
        var title: String
        var start: Date
        var isAllDay: Bool
        var courseName: String?
        var isSubmitted: Bool
    }

    var habits: [HabitLine] = []
    var events: [EventLine] = []
    var doneToday: Int = 0
    var totalToday: Int = 0
    var xp: Int = 0
    var rankTitle: String = "ROOKIE"
    var updated: Date = Date()
}

/// Shared read/write point for the widget snapshot.
///
/// `appGroupID` must match the App Group you enable on BOTH the app target and
/// the widget target in Xcode (Signing & Capabilities → + Capability → App Groups).
/// If the group isn't set up, everything here degrades quietly to a no-op.
enum WidgetBridge {

    static let appGroupID = "group.com.sid.retrohabits"
    private static let fileName = "widget-snapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    // MARK: Reading (widget side)

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return nil }
        return snapshot
    }

    // MARK: Writing (app side)

    private static func write(_ transform: (inout WidgetSnapshot) -> Void) {
        guard let url = fileURL else { return }
        var snapshot = loadSnapshot() ?? WidgetSnapshot()
        transform(&snapshot)
        snapshot.updated = Date()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func publish(habits: [Habit]) {
        let today = Date()
        let todays = habits.filter { $0.isScheduled(on: today) }
        let lines = todays.prefix(6).map { habit in
            WidgetSnapshot.HabitLine(
                id: habit.id.uuidString,
                name: habit.name,
                icon: habit.icon,
                done: habit.isCompleted(on: today),
                streak: habit.streak
            )
        }
        let xp = Gamification.totalXP(habits)
        write { snapshot in
            snapshot.habits = Array(lines)
            snapshot.doneToday = todays.filter { $0.isCompleted(on: today) }.count
            snapshot.totalToday = todays.count
            snapshot.xp = xp
            snapshot.rankTitle = HeroRank.rank(for: xp).title
        }
    }

    static func publish(agenda items: [AgendaItem]) {
        let upcoming = items
            .filter { $0.start >= Calendar.current.startOfDay(for: Date()) }
            .prefix(6)
            .map { item in
                WidgetSnapshot.EventLine(
                    id: item.id,
                    title: item.title,
                    start: item.start,
                    isAllDay: item.isAllDay,
                    courseName: item.courseName,
                    isSubmitted: item.isSubmitted
                )
            }
        write { snapshot in
            snapshot.events = Array(upcoming)
        }
    }
}
