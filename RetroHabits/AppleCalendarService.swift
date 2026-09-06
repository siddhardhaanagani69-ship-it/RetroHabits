import Foundation
import EventKit

/// Reads events from the iPhone's calendars via EventKit.
/// This automatically covers every app that syncs into the iPhone Calendar
/// (Apple Calendar, subscribed feeds, Google, and so on).
struct AppleCalendarService {

    nonisolated(unsafe) private static let store = EKEventStore()

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func fetchItems(days: Int = 7) async -> [AgendaItem] {
        let granted = await requestAccess()
        guard granted else { return [] }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        return events.compactMap { event in
            guard let startDate = event.startDate else { return nil }
            var notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed = notes, trimmed.count > 900 {
                notes = String(trimmed.prefix(900)) + "…"
            }
            return AgendaItem(
                id: "ek-\(event.eventIdentifier ?? UUID().uuidString)-\(Int(startDate.timeIntervalSince1970))",
                title: event.title ?? "(No title)",
                start: startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                location: (event.location?.isEmpty == false) ? event.location : nil,
                notes: (notes?.isEmpty == false) ? notes : nil,
                url: event.url,
                source: .apple
            )
        }
    }
}
