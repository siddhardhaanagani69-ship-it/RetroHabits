import Foundation
import Combine

/// How far ahead alerts fire.
enum LeadTimeProfile: String, CaseIterable, Identifiable {
    case earlyWarning
    case standard
    case lastMinute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .earlyWarning: return "EARLY WARNING"
        case .standard: return "STANDARD"
        case .lastMinute: return "LAST MINUTE"
        }
    }

    /// Hours before a deadline to fire assignment alerts.
    var assignmentLeadHours: [Int] {
        switch self {
        case .earlyWarning: return [72, 24, 3]
        case .standard: return [24, 2]
        case .lastMinute: return [3]
        }
    }

    /// Minutes before an event starts.
    var eventLeadMinutes: Int {
        switch self {
        case .earlyWarning: return 30
        case .standard: return 15
        case .lastMinute: return 10
        }
    }

    var summary: String {
        switch self {
        case .earlyWarning: return "Deadlines: 3 days, 1 day, 3 hours before. Events: 30 min before."
        case .standard: return "Deadlines: 1 day and 2 hours before. Events: 15 min before."
        case .lastMinute: return "Deadlines: 3 hours before. Events: 10 min before."
        }
    }
}

/// User-facing alert settings, stored in UserDefaults.
@MainActor
final class AlertPreferences: ObservableObject {

    static let shared = AlertPreferences()

    @Published var deadlineAlertsEnabled: Bool {
        didSet { store(deadlineAlertsEnabled, "alerts_deadlines") }
    }
    @Published var eventAlertsEnabled: Bool {
        didSet { store(eventAlertsEnabled, "alerts_events") }
    }
    @Published var dailyBriefingEnabled: Bool {
        didSet { store(dailyBriefingEnabled, "alerts_briefing") }
    }
    @Published var briefingHour: Int {
        didSet { store(briefingHour, "alerts_briefing_hour") }
    }
    @Published var deadlineWatchEnabled: Bool {
        didSet { store(deadlineWatchEnabled, "alerts_watch") }
    }
    @Published var watchHour: Int {
        didSet { store(watchHour, "alerts_watch_hour") }
    }
    /// How many days ahead the deadline-watch digest looks.
    @Published var watchWindowDays: Int {
        didSet { store(watchWindowDays, "alerts_watch_days") }
    }
    @Published var profile: LeadTimeProfile {
        didSet { store(profile.rawValue, "alerts_profile") }
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "alerts_deadlines": true,
            "alerts_events": true,
            "alerts_briefing": true,
            "alerts_briefing_hour": 8,
            "alerts_watch": true,
            "alerts_watch_hour": 19,
            "alerts_watch_days": 3,
            "alerts_profile": LeadTimeProfile.earlyWarning.rawValue
        ])
        deadlineAlertsEnabled = defaults.bool(forKey: "alerts_deadlines")
        eventAlertsEnabled = defaults.bool(forKey: "alerts_events")
        dailyBriefingEnabled = defaults.bool(forKey: "alerts_briefing")
        briefingHour = defaults.integer(forKey: "alerts_briefing_hour")
        deadlineWatchEnabled = defaults.bool(forKey: "alerts_watch")
        watchHour = defaults.integer(forKey: "alerts_watch_hour")
        watchWindowDays = defaults.integer(forKey: "alerts_watch_days")
        profile = LeadTimeProfile(rawValue: defaults.string(forKey: "alerts_profile") ?? "") ?? .earlyWarning
    }

    private func store(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
