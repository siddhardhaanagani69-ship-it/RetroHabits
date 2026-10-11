import Foundation
import SwiftUI

/// Combines Canvas (API token or .ics feed) and iPhone calendar items into one agenda.
@MainActor
final class AgendaStore: ObservableObject {

    /// Single instance shared by the UI and the background-refresh handler,
    /// so a background wake updates the same store the app is showing.
    static let shared = AgendaStore()

    @Published var items: [AgendaItem] = []
    /// Recent important email for the Inbox panel (empty when Gmail isn't connected).
    @Published var mails: [AssistantService.MailBrief] = []
    @Published var isLoading = false
    @Published var errors: [String] = []
    @Published var lastRefreshed: Date?
    /// Hide work that's already turned in.
    @Published var hideSubmitted = false

    // MARK: Stored settings

    var canvasFeedURL: String {
        get { UserDefaults.standard.string(forKey: "canvas_feed_url") ?? "" }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "canvas_feed_url")
        }
    }

    var canvasHost: String {
        get { UserDefaults.standard.string(forKey: "canvas_host") ?? "" }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "canvas_host")
        }
    }

    /// Stored in the Keychain, not UserDefaults — it's a credential.
    /// Cached in memory because SwiftUI reads this during view updates and a
    /// Keychain hit on the main thread every pass is expensive.
    private var cachedToken: String?

    var canvasToken: String {
        get {
            if let cachedToken { return cachedToken }
            let value = Keychain.data(forKey: "canvas_token")
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            cachedToken = value
            return value
        }
        set {
            objectWillChange.send()
            cachedToken = newValue
            if newValue.isEmpty {
                Keychain.delete(forKey: "canvas_token")
            } else {
                Keychain.set(Data(newValue.utf8), forKey: "canvas_token")
            }
        }
    }

    var appleCalendarEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "apple_calendar_enabled") }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "apple_calendar_enabled")
        }
    }

    var usesCanvasAPI: Bool {
        !canvasToken.trimmingCharacters(in: .whitespaces).isEmpty
            && !canvasHost.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: Refresh

    func refresh() async {
        // The scene-phase handler and the view's .task can both fire at launch.
        guard !isLoading else { return }
        isLoading = true
        errors = []
        var collected: [AgendaItem] = []

        // Canvas — the API token gives far richer data, so it wins when present.
        if usesCanvasAPI {
            do {
                let credentials = CanvasAPIService.Credentials(host: canvasHost, token: canvasToken)
                collected += try await CanvasAPIService.fetchPlannerItems(credentials: credentials)
            } catch {
                errors.append("Canvas: \(error.localizedDescription)")
            }
        } else if !canvasFeedURL.trimmingCharacters(in: .whitespaces).isEmpty {
            do {
                let canvasItems = try await CanvasService.fetchItems(feedURLString: canvasFeedURL)
                let cutoff = Calendar.current.date(byAdding: .day, value: 21, to: Date())!
                collected += canvasItems.filter {
                    $0.start >= Calendar.current.startOfDay(for: Date()) && $0.start <= cutoff
                }
            } catch {
                errors.append("Canvas: \(error.localizedDescription)")
            }
        }

        // iPhone calendars (anything synced to the phone, incl. Outlook/Teams
        // if the school account is added to iOS Calendar)
        if appleCalendarEnabled {
            collected += await AppleCalendarService.fetchItems(days: 7)
        }

        // De-duplicate near-identical events — prefer the Canvas copy, which
        // carries the course name and submission status.
        var seen = Set<String>()
        var deduped: [AgendaItem] = []
        for item in collected.sorted(by: { sourceRank($0.source) < sourceRank($1.source) }) {
            let key = "\(item.title.lowercased())|\(Int(item.start.timeIntervalSince1970 / 60))"
            if seen.insert(key).inserted {
                deduped.append(item)
            }
        }

        items = deduped.sorted { $0.start < $1.start }

        // Glance summaries from the assistant backend. Raw items are already on
        // screen, so if the backend is down the agenda still works.
        if !items.isEmpty {
            do {
                let summaries = try await AssistantService.summaries(for: items)
                for index in items.indices {
                    guard let s = summaries[items[index].id] else { continue }
                    items[index].summary = s.summary
                    items[index].action = s.action.isEmpty ? nil : s.action
                    items[index].urgency = s.urgency
                    if items[index].courseName == nil { items[index].courseName = s.course }
                }
            } catch {
                errors.append("Assistant: \(error.localizedDescription)")
            }
        }

        // Email (incl. Teams notifications): the inbox, plus any deadline or meeting an email
        // states, as agenda items — so they get alerts and Ripple sees them. Optional:
        // skipped quietly when Gmail isn't connected.
        if let mail = try? await AssistantService.mail() {
            mails = mail
            let today = Calendar.current.startOfDay(for: Date())
            items += mail.compactMap { m -> AgendaItem? in
                guard let due = m.due, due >= today else { return nil }
                return AgendaItem(id: "mail-\(m.id)", title: m.subject, start: due, end: m.dueEnd,
                                  notes: m.excerpt, url: m.link, source: .email,
                                  kind: m.dueEnd == nil ? .assignment : .event,
                                  summary: m.summary, action: m.action.isEmpty ? nil : m.action, urgency: m.urgency)
            }
            items.sort { $0.start < $1.start }
        }

        lastRefreshed = Date()
        isLoading = false

        // Rebuild alerts from the fresh data.
        await NotificationScheduler.shared.reschedule(
            items: items,
            preferences: AlertPreferences.shared
        )

        WidgetBridge.publish(agenda: visibleItems)
    }

    private func sourceRank(_ source: AgendaSource) -> Int {
        switch source {
        case .canvas: return 0
        case .apple: return 1
        case .email: return 2
        }
    }

    // MARK: Derived

    var visibleItems: [AgendaItem] {
        hideSubmitted ? items.filter { !$0.isSubmitted } : items
    }

    /// Items grouped by day, in chronological order.
    var itemsByDay: [(day: Date, items: [AgendaItem])] {
        let groups = Dictionary(grouping: visibleItems) { Calendar.current.startOfDay(for: $0.start) }
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { $0.start < $1.start }) }
    }

    var submittedCount: Int {
        items.filter { $0.isSubmitted }.count
    }

    var missingCount: Int {
        items.filter { $0.isMissing }.count
    }
}
