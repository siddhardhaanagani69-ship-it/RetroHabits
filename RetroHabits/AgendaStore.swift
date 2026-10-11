import Foundation
import SwiftUI

/// Combines Canvas (API token or .ics feed) and iPhone calendar items into one agenda.
@MainActor
final class AgendaStore: ObservableObject {

    /// Single instance shared by the UI and the background-refresh handler,
    /// so a background wake updates the same store the app is showing.
    static let shared = AgendaStore()

    private init() {
        mergeRoutines()   // classes and shifts show before the first network refresh
    }

    @Published var items: [AgendaItem] = []
    /// Recent important email for the Inbox panel (empty when Gmail isn't connected).
    @Published var mails: [AssistantService.MailBrief] = []
    @Published var isLoading = false
    @Published var errors: [String] = []
    @Published var lastRefreshed: Date?
    /// Hide work that's already turned in.
    @Published var hideSubmitted = false

    /// Work you've marked as turned in (and Canvas submissions already recorded),
    /// kept on the phone so the mark survives refreshes of an .ics feed.
    private var submittedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "submitted_item_ids") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "submitted_item_ids") }
    }

    /// Mark work turned in (or not), and record it so Ask can say when it was submitted.
    func setSubmitted(_ item: AgendaItem, _ submitted: Bool) {
        if submitted {
            submittedIDs.insert(item.id)
            AssistantService.recordHistory(ref: "submit-\(item.id)", kind: "submitted", title: item.title,
                                           detail: Self.submissionDetail(item))
        } else {
            submittedIDs.remove(item.id)
            AssistantService.deleteHistory(ref: "submit-\(item.id)")
        }
        for index in items.indices where items[index].id == item.id { items[index].isSubmitted = submitted }
    }

    private static func submissionDetail(_ item: AgendaItem) -> String {
        [item.courseName, "due \(item.start.formatted(date: .abbreviated, time: .shortened))"]
            .compactMap { $0 }.joined(separator: ", ")
    }

    /// Canvas reports some submissions itself: record each once. Then show every
    /// remembered mark, since an .ics feed never says what was turned in.
    private func applySubmissions() {
        var known = submittedIDs
        for item in items where item.isSubmitted && !known.contains(item.id) {
            known.insert(item.id)
            AssistantService.recordHistory(ref: "submit-\(item.id)", kind: "submitted", title: item.title,
                                           detail: (Self.submissionDetail(item) + ", seen on Canvas"))
        }
        submittedIDs = known
        for index in items.indices where known.contains(items[index].id) { items[index].isSubmitted = true }
    }

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
        mergeRoutines()   // right away, so classes never blink out during a refresh

        // Glance summaries from the assistant backend. Raw items are already on
        // screen, so if the backend is down the agenda still works.
        if !items.isEmpty {
            do {
                // Classes and shifts are the user's own words: nothing to summarize, no quota spent.
                let summaries = try await AssistantService.summaries(for: items.filter { $0.source != .routine })
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

        applySubmissions()
        await MoneyStore.shared.refresh()   // the budget line on the home screen
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
        case .routine: return 3
        }
    }

    /// Puts the next two weeks of classes and shifts into the agenda. Local and
    /// instant, so it also runs whenever a routine is added, edited or deleted.
    func mergeRoutines() {
        items.removeAll { $0.source == .routine }
        items += RoutineStore.shared.routines.flatMap { $0.occurrences() }
        items.sort { $0.start < $1.start }
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
