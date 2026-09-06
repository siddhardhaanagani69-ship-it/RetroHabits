import Foundation
import Combine
import UserNotifications

/// One alert the app has scheduled — used for both the system notification
/// and the in-app Alerts feed.
struct ScheduledAlert: Identifiable, Equatable {
    enum Kind: String {
        case deadline, event, briefing, watch

        var label: String {
            switch self {
            case .deadline: return "DEADLINE"
            case .event: return "EVENT"
            case .briefing: return "BRIEFING"
            case .watch: return "DEADLINE WATCH"
            }
        }

        var symbol: String {
            switch self {
            case .deadline: return "exclamationmark.triangle.fill"
            case .event: return "clock.fill"
            case .briefing: return "sun.max.fill"
            case .watch: return "binoculars.fill"
            }
        }
    }

    var id: String
    var kind: Kind
    var title: String
    var body: String
    var fireDate: Date
    /// The agenda item this alert is about, when there is one.
    var itemID: String?
}

/// Builds and schedules all agenda-derived local notifications.
///
/// Note: iOS does not allow one app to read another app's notifications —
/// there is no API for it on iPhone. Instead this generates its own alerts
/// from the Canvas and calendar data the app already syncs.
@MainActor
final class NotificationScheduler: ObservableObject {

    static let shared = NotificationScheduler()

    /// Everything currently scheduled, newest first — drives the Alerts tab.
    @Published private(set) var alerts: [ScheduledAlert] = []
    @Published private(set) var authorizationDenied = false

    /// iOS caps pending local notifications at 64 per app — habit reminders
    /// share that budget, so the agenda's share is whatever they leave.
    private let systemLimit = 62
    private let minimumAgendaSlots = 20
    private let prefix = "agenda-alert-"

    private init() {}

    // MARK: - Permission

    @discardableResult
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        authorizationDenied = !granted
        return granted
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationDenied = settings.authorizationStatus == .denied
    }

    // MARK: - Scheduling

    /// Rebuilds every agenda-derived alert from the current items.
    /// Safe to call on each refresh — it clears its own previous alerts first.
    func reschedule(items: [AgendaItem], preferences: AlertPreferences) async {
        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            authorizationDenied = settings.authorizationStatus == .denied
            alerts = []
            return
        }

        // Clear previously scheduled agenda alerts (leaves habit reminders alone).
        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)

        // Whatever habit reminders occupy is off-limits to agenda alerts.
        let othersPending = pending.count - staleIDs.count
        let maxPending = max(minimumAgendaSlots, systemLimit - othersPending)

        var built: [ScheduledAlert] = []
        let now = Date()

        // 1. Deadline alerts (Canvas assignments and other dated items).
        if preferences.deadlineAlertsEnabled {
            for item in items where item.source == .canvas {
                for hours in preferences.profile.assignmentLeadHours {
                    guard let fire = Calendar.current.date(byAdding: .hour, value: -hours, to: item.start),
                          fire > now else { continue }
                    built.append(ScheduledAlert(
                        id: "\(prefix)deadline-\(item.id)-\(hours)",
                        kind: .deadline,
                        title: dueTitle(hoursBefore: hours),
                        body: "\(item.title) — due \(Self.friendly(item.start)).",
                        fireDate: fire,
                        itemID: item.id
                    ))
                }
            }
        }

        // 2. Event start alerts — only for things that *happen* at a time.
        //    Submittable Canvas work is covered by the deadline pass above.
        if preferences.eventAlertsEnabled {
            let minutes = preferences.profile.eventLeadMinutes
            for item in items where !item.isAllDay && !item.kind.isSubmittable {
                guard let fire = Calendar.current.date(byAdding: .minute, value: -minutes, to: item.start),
                      fire > now else { continue }
                var body = "Starts at \(Self.timeFormatter.string(from: item.start))"
                if let location = item.location { body += " · \(location)" }
                built.append(ScheduledAlert(
                    id: "\(prefix)event-\(item.id)",
                    kind: .event,
                    title: "⏰ In \(minutes) min: \(item.title)",
                    body: body,
                    fireDate: fire,
                    itemID: item.id
                ))
            }
        }

        // 3. Daily morning briefing — one per day for the next week, with the
        //    actual contents of that day baked in.
        if preferences.dailyBriefingEnabled {
            built += briefings(items: items, hour: preferences.briefingHour, now: now)
        }

        // 4. Deadline watch — a recurring nudge listing what's due in the next
        //    few days, so nothing sneaks up on you.
        if preferences.deadlineWatchEnabled {
            built += deadlineWatches(
                items: items,
                hour: preferences.watchHour,
                windowDays: preferences.watchWindowDays,
                now: now
            )
        }

        // Nearest alerts win if we exceed the iOS limit.
        let sorted = built.sorted { $0.fireDate < $1.fireDate }
        let capped = Array(sorted.prefix(maxPending))

        for alert in capped {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            if let itemID = alert.itemID {
                content.userInfo = ["itemID": itemID]
            }
            let interval = max(1, alert.fireDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger)
            try? await center.add(request)
        }

        alerts = capped
    }

    /// Removes every agenda alert (used when the user turns alerts off).
    func clearAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        alerts = []
    }

    // MARK: - Builders

    private func briefings(items: [AgendaItem], hour: Int, now: Date) -> [ScheduledAlert] {
        let calendar = Calendar.current
        var result: [ScheduledAlert] = []

        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                  fire > now else { continue }

            let dayItems = items
                .filter { calendar.isDate($0.start, inSameDayAs: day) }
                .sorted { $0.start < $1.start }
            guard !dayItems.isEmpty else { continue }

            let headline = dayItems.prefix(3).map { item -> String in
                item.isAllDay ? item.title : "\(Self.timeFormatter.string(from: item.start)) \(item.title)"
            }.joined(separator: " · ")
            let extra = dayItems.count > 3 ? " (+\(dayItems.count - 3) more)" : ""

            result.append(ScheduledAlert(
                id: "\(prefix)briefing-\(calendar.startOfDay(for: day).timeIntervalSince1970)",
                kind: .briefing,
                title: "☀️ Today: \(dayItems.count) thing\(dayItems.count == 1 ? "" : "s") on deck",
                body: headline + extra,
                fireDate: fire,
                itemID: nil
            ))
        }
        return result
    }

    private func deadlineWatches(items: [AgendaItem], hour: Int, windowDays: Int, now: Date) -> [ScheduledAlert] {
        let calendar = Calendar.current
        var result: [ScheduledAlert] = []

        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                  fire > now,
                  let windowEnd = calendar.date(byAdding: .day, value: windowDays, to: fire) else { continue }

            let upcoming = items
                .filter { $0.source == .canvas && $0.start > fire && $0.start <= windowEnd }
                .sorted { $0.start < $1.start }
            guard !upcoming.isEmpty else { continue }

            let list = upcoming.prefix(3).map { "\($0.title) (\(Self.shortDate($0.start)))" }
                .joined(separator: " · ")
            let extra = upcoming.count > 3 ? " (+\(upcoming.count - 3) more)" : ""

            result.append(ScheduledAlert(
                id: "\(prefix)watch-\(calendar.startOfDay(for: day).timeIntervalSince1970)",
                kind: .watch,
                title: "🔭 \(upcoming.count) deadline\(upcoming.count == 1 ? "" : "s") in the next \(windowDays) days",
                body: list + extra,
                fireDate: fire,
                itemID: nil
            ))
        }
        return result
    }

    private func dueTitle(hoursBefore: Int) -> String {
        switch hoursBefore {
        case let h where h >= 48: return "📌 Due in \(h / 24) days"
        case let h where h >= 24: return "📌 Due tomorrow"
        default: return "🚨 Due in \(hoursBefore) hour\(hoursBefore == 1 ? "" : "s")"
        }
    }

    // MARK: - Formatting

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func friendly(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today at \(timeFormatter.string(from: date))" }
        if calendar.isDateInTomorrow(date) { return "tomorrow at \(timeFormatter.string(from: date))" }
        return "\(shortDate(date)) at \(timeFormatter.string(from: date))"
    }
}
