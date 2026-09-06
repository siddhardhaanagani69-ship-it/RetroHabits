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

    private func scheduleReminders(for habit: Habit) {
        cancelReminders(for: habit)
        guard let hour = habit.reminderHour, let minute = habit.reminderMinute else { return }
        let center = UNUserNotificationCenter.current()
        for weekday in habit.scheduledWeekdays {
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            let content = UNMutableNotificationContent()
            content.title = "▶ \(habit.name.uppercased())"
            content.body = "Time to keep the streak alive! Currently: \(habit.streak) days."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "habit-\(habit.id.uuidString)-\(weekday)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func cancelReminders(for habit: Habit) {
        let ids = (1...7).map { "habit-\(habit.id.uuidString)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
