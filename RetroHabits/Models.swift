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

    var hasReminder: Bool { reminderHour != nil && reminderMinute != nil }

    /// Built once — `streak` and the stats grid call this thousands of times
    /// per render, and a fresh DateFormatter each time is very expensive.
    nonisolated(unsafe) private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(for date: Date) -> String {
        keyFormatter.string(from: date)
    }

    func isCompleted(on date: Date) -> Bool {
        completedDays.contains(Habit.dayKey(for: date))
    }

    func isScheduled(on date: Date) -> Bool {
        scheduledWeekdays.contains(Calendar.current.component(.weekday, from: date))
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
        case .assignment: return "ASSIGNMENT"
        case .quiz: return "QUIZ"
        case .discussion: return "DISCUSSION"
        case .event: return "EVENT"
        case .note: return "NOTE"
        case .announcement: return "NEWS"
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

    var pointsText: String? {
        guard let points = pointsPossible, points > 0 else { return nil }
        let whole = points.rounded()
        return abs(points - whole) < 0.01 ? "\(Int(whole)) pts" : String(format: "%.1f pts", points)
    }
}
