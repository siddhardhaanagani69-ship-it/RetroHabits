import Foundation
import Combine
import UserNotifications

@MainActor
final class HabitStore: ObservableObject {
    /// Single instance, so the widget bridge and the UI always agree.
    static let shared = HabitStore()

    @Published var habits: [Habit] = [] {
        didSet {
            save()
            WidgetBridge.publish(habits: habits)
        }
    }

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("habits.json")
    }()

    init() {
        load()
        WidgetBridge.publish(habits: habits)
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Habit].self, from: data) else { return }
        habits = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(habits) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Mutations

    func add(_ habit: Habit) {
        habits.append(habit)
        scheduleReminders(for: habit)
    }

    func update(_ habit: Habit) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        habits[index] = habit
        scheduleReminders(for: habit)
    }

    func delete(_ habit: Habit) {
        habits.removeAll { $0.id == habit.id }
        cancelReminders(for: habit)
    }

    func toggleToday(_ habit: Habit) {
        guard let index = habits.firstIndex(where: { $0.id == habit.id }) else { return }
        let key = Habit.dayKey(for: Date())
        if habits[index].completedDays.contains(key) {
            habits[index].completedDays.remove(key)
        } else {
            habits[index].completedDays.insert(key)
        }
    }

    // MARK: Derived

    var todaysHabits: [Habit] {
        habits.filter { $0.isScheduled(on: Date()) }
    }

    var todayProgress: Double {
        let todays = todaysHabits
        guard !todays.isEmpty else { return 0 }
        let done = todays.filter { $0.isCompleted(on: Date()) }.count
        return Double(done) / Double(todays.count)
    }

    // MARK: Notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Accept a Ripple Mode reschedule: this one occurrence moves, the weekly plan stays.
    func applyMove(habitID: UUID, originalDay: String, to start: Date) {
        guard let index = habits.firstIndex(where: { $0.id == habitID }) else { return }
        habits[index].moves = (habits[index].moves ?? [:]).merging([originalDay: start]) { _, new in new }
        scheduleReminders(for: habits[index])
    }

    /// Re-run on every foreground/background wake: a weekday reminder skipped
    /// because of a move comes back once that day has passed, and the streak
    /// count in the notification text stays current.
    func refreshReminders() {
        habits.forEach(scheduleReminders)
    }

    private func scheduleReminders(for habit: Habit) {
        cancelReminders(for: habit)
        guard let hour = habit.reminderHour, let minute = habit.reminderMinute else { return }
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let now = Date()
        let moves = habit.moves ?? [:]

        func add(_ id: String, _ components: DateComponents, repeats: Bool) {
            let content = UNMutableNotificationContent()
            content.title = habit.name
            content.body = "Time to keep the streak alive! Currently: \(habit.streak) days."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }

        for weekday in habit.scheduledWeekdays {
            let components = DateComponents(hour: hour, minute: minute, weekday: weekday)
            // A repeating trigger can't skip one week, so if the next occurrence was
            // moved, leave it off until that day passes (refreshReminders restores it).
            if let next = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime),
               moves[Habit.dayKey(for: next)] != nil { continue }
            add("habit-\(habit.id.uuidString)-\(weekday)", components, repeats: true)
        }
        for (day, start) in moves where start > now {
            add("habit-\(habit.id.uuidString)-move-\(day)",
                calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start), repeats: false)
        }
    }

    private func cancelReminders(for habit: Habit) {
        let ids = (1...7).map { "habit-\(habit.id.uuidString)-\($0)" }
            + (habit.moves ?? [:]).keys.map { "habit-\(habit.id.uuidString)-move-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
