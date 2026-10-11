import Foundation

/// Something that repeats at a set time — a class, a work shift, a bill.
/// Unlike a habit there's nothing to check off; it's a fixed item in your week
/// with a reminder before it.
struct Routine: Identifiable, Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case lecture, shift, bill, other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .lecture: "Class"
            case .shift: "Shift"
            case .bill: "Bill"
            case .other: "Other"
            }
        }

        var symbol: String {
            switch self {
            case .lecture: "graduationcap.fill"
            case .shift: "briefcase.fill"
            case .bill: "creditcard.fill"
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
    /// Bills: the amount due. Optional so routines saved before bills existed still decode.
    var amount: Double?
    /// Shifts: pay per hour, for this week's planned income.
    var hourlyRate: Double?
    /// Bills due monthly: the day of the month (1–28). nil = weekly on `weekdays`.
    var monthlyDay: Int?

    func occurs(on day: Date) -> Bool {
        let calendar = Calendar.current
        if let monthlyDay { return calendar.component(.day, from: day) == monthlyDay }
        return weekdays.contains(calendar.component(.weekday, from: day))
    }

    /// Planned pay for one shift (nil unless it's a shift with a rate).
    var payPerOccurrence: Double? {
        guard kind == .shift, let hourlyRate else { return nil }
        return hourlyRate * Double(durationMinutes) / 60
    }

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
                  occurs(on: day),
                  let start = start(on: day) else { return nil }
            // A bill is a due date, not a block of time: all-day, so it never "conflicts".
            let isBill = kind == .bill
            return AgendaItem(
                id: "routine-\(id.uuidString)-\(Habit.dayKey(for: day))",
                title: isBill ? "\(name) due" + (amount.map { " · \($0.formatted(.currency(code: Routine.currency)))" } ?? "") : name,
                start: start,
                end: isBill ? nil : start.addingTimeInterval(TimeInterval(durationMinutes * 60)),
                isAllDay: isBill,
                location: location,
                source: .routine,
                kind: isBill ? .note : .event
            )
        }
    }

    /// The user's currency, for formatting amounts.
    static var currency: String { Locale.current.currency?.identifier ?? "USD" }
}
