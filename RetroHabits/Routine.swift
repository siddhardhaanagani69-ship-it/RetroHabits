import Foundation

/// Something that repeats every week at a set time — a class, a work shift.
/// Unlike a habit there's nothing to check off; it's a fixed block in your week
/// with a reminder before it starts.
struct Routine: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case lecture, shift, other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .lecture: "Class"
            case .shift: "Shift"
            case .other: "Other"
            }
        }

        var symbol: String {
            switch self {
            case .lecture: "graduationcap.fill"
            case .shift: "briefcase.fill"
            case .other: "repeat"
            }
        }
    }

    var id = UUID()
    var name: String
    var kind: Kind = .lecture
    /// 1 = Sunday ... 7 = Saturday, matching Calendar.component(.weekday).
    var weekdays: Set<Int>
    var startHour: Int
    var startMinute: Int
    var durationMinutes: Int
    var location: String?
    /// Minutes before the start to send a reminder; nil = no reminder.
    var remindMinutesBefore: Int?

    func start(on day: Date) -> Date? {
        Calendar.current.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day)
    }

    /// One agenda item per scheduled day in the next `days` days, so the day plan,
    /// alerts and Ripple treat it like any other fixed event.
    func occurrences(from today: Date = .now, days: Int = 14) -> [AgendaItem] {
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: today)
        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: first),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let start = start(on: day) else { return nil }
            return AgendaItem(
                id: "routine-\(id.uuidString)-\(Habit.dayKey(for: day))",
                title: name,
                start: start,
                end: start.addingTimeInterval(TimeInterval(durationMinutes * 60)),
                location: location,
                source: .routine,
                kind: .event
            )
        }
    }
}
