import Foundation

// MARK: - Habit

struct Habit: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var icon: String = "⭐️"
    /// Weekdays this habit is scheduled (1 = Sunday ... 7 = Saturday, matching Calendar.component(.weekday)).
    var scheduledWeekdays: Set<Int> = [1, 2, 3, 4, 5, 6, 7]
    /// Optional daily reminder (hour/minute in local time).
    var reminderHour: Int?
    var reminderMinute: Int?
    var createdAt = Date()
    /// Days completed, stored as "yyyy-MM-dd" strings in local time.
    var completedDays: Set<String> = []
    /// How long a session takes — with the reminder time, this makes it a planned
    /// session that Ripple Mode can check for conflicts. Optional so older saved
    /// habits (without the key) still decode.
    var durationMinutes: Int?
    /// One-off reschedules accepted in Ripple Mode: original day ("yyyy-MM-dd") -> new start.
    /// Moving a session is a plan change, never a completion.
    var moves: [String: Date]?

    var hasReminder: Bool { reminderHour != nil && reminderMinute != nil }
    var duration: Int { durationMinutes ?? 60 }

    /// "yyyy-MM-dd" in local time. Streaks and the stats grid call this thousands of
    /// times per render; building it from calendar components is ~2.5x faster than a
    /// DateFormatter, with identical output.
    static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let (y, m, d) = (c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return "\(y)-\(m < 10 ? "0" : "")\(m)-\(d < 10 ? "0" : "")\(d)"
    }

    func isCompleted(on date: Date) -> Bool {
        completedDays.contains(Habit.dayKey(for: date))
    }

    func isScheduled(on date: Date) -> Bool {
        if let moves, !moves.isEmpty {
            let key = Habit.dayKey(for: date)
            if moves.values.contains(where: { Habit.dayKey(for: $0) == key }) { return true }
            if moves[key] != nil { return false }
        }
        return scheduledWeekdays.contains(Calendar.current.component(.weekday, from: date))
    }

    /// Consecutive scheduled days completed, counting back from today.
    /// Today not being done yet does not break the streak.
    var streak: Int {
        let calendar = Calendar.current
        var count = 0
        for offset in 0..<730 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: Date()) else { break }
            guard isScheduled(on: day) else { continue }
            if isCompleted(on: day) {
                count += 1
            } else if offset == 0 {
                continue
            } else {
                break
            }
        }
        return count
    }

    /// Longest run of scheduled days ever completed — drives milestone rewards.
    var longestStreak: Int {
        let key = LongestKey(id: id, done: completedDays.count, weekdays: scheduledWeekdays,
                             moves: moves, today: Habit.dayKey(for: Date()))
        if let cached = Habit.longestCache[key] { return cached }
        let value = computeLongestStreak()
        if Habit.longestCache.count > 500 { Habit.longestCache.removeAll() }
        Habit.longestCache[key] = value
        return value
    }

    /// Stats, XP, achievements and the widget each ask for the longest streak, often
    /// several times per habit per render, and computing it walks every day since the
    /// habit was created — so results are remembered per habit state. Completions only
    /// ever toggle today's key, so the count (plus schedule, moves and date) catches
    /// every change.
    private struct LongestKey: Hashable {
        let id: UUID, done: Int, weekdays: Set<Int>, moves: [String: Date]?, today: String
    }
    // ponytail: one process-wide memo, read and written on the main thread only; swap for a per-store cache if habits are ever computed off-main.
    nonisolated(unsafe) private static var longestCache: [LongestKey: Int] = [:]

    private func computeLongestStreak() -> Int {
        let calendar = Calendar.current
        var best = 0
        var running = 0
        // Walk forward from creation day to today.
        let start = calendar.startOfDay(for: createdAt)
        let today = calendar.startOfDay(for: Date())
        guard let dayCount = calendar.dateComponents([.day], from: start, to: today).day else { return streak }
        for offset in 0...max(0, min(dayCount, 730)) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { break }
            guard isScheduled(on: day) else { continue }
            if isCompleted(on: day) {
                running += 1
                best = max(best, running)
            } else if day < today {
                running = 0
            }
        }
        return max(best, streak)
    }
}

// MARK: - Agenda

enum AgendaSource: String, Codable, CaseIterable {
    case canvas = "CANVAS"
    case apple = "IPHONE"
    case email = "EMAIL"
    case routine = "ROUTINE"
}

/// What kind of thing an agenda item is — drives the icon and wording.
enum AgendaItemKind: String, Codable {
    case assignment, quiz, discussion, event, note, announcement

    init(canvasType: String) {
        switch canvasType.lowercased() {
        case "quiz": self = .quiz
        case "discussion_topic": self = .discussion
        case "calendar_event": self = .event
        case "planner_note": self = .note
        case "announcement": self = .announcement
        default: self = .assignment
        }
    }

    var symbol: String {
        switch self {
        case .assignment: return "doc.text.fill"
        case .quiz: return "questionmark.square.fill"
        case .discussion: return "bubble.left.and.bubble.right.fill"
        case .event: return "calendar"
        case .note: return "pin.fill"
        case .announcement: return "megaphone.fill"
        }
    }

    var label: String {
        switch self {
        case .assignment: return "Assignment"
        case .quiz: return "Quiz"
        case .discussion: return "Discussion"
        case .event: return "Event"
        case .note: return "Note"
        case .announcement: return "News"
        }
    }

    /// Items that represent work you turn in (as opposed to something that just happens).
    var isSubmittable: Bool {
        switch self {
        case .assignment, .quiz, .discussion: return true
        case .event, .note, .announcement: return false
        }
    }
}

struct AgendaItem: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date?
    var isAllDay: Bool = false
    var location: String?
    var notes: String?
    var url: URL?
    var source: AgendaSource

    // Canvas API extras (nil/false when the data came from the .ics feed).
    var courseName: String?
    var kind: AgendaItemKind = .event
    var isSubmitted: Bool = false
    var isMissing: Bool = false
    var isGraded: Bool = false
    var pointsPossible: Double?

    // Assistant glance card (nil until the backend has summarized it).
    var summary: String?
    var action: String?
    var urgency: Int?

    var pointsText: String? {
        guard let points = pointsPossible, points > 0 else { return nil }
        let whole = points.rounded()
        return abs(points - whole) < 0.01 ? "\(Int(whole)) pts" : String(format: "%.1f pts", points)
    }
}
