import Foundation

/// Talks to the Canvas REST API with a personal access token.
///
/// This is a big upgrade over the .ics feed: the planner endpoint returns the
/// course name, whether you've already submitted, how many points it's worth,
/// and a direct link to the assignment page.
///
/// Get a token in Canvas: Account → Settings → "+ New Access Token".
struct CanvasAPIService {

    struct Credentials {
        var host: String
        var token: String

        /// Accepts "canvas.uh.edu", "https://canvas.uh.edu", or a full URL with a path.
        var baseURL: URL? {
            var text = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            if !text.lowercased().hasPrefix("http") {
                text = "https://" + text
            }
            guard var components = URLComponents(string: text), let hostName = components.host else { return nil }
            components.scheme = "https"
            components.host = hostName
            components.path = ""
            components.query = nil
            components.fragment = nil
            return components.url
        }
    }

    enum CanvasError: LocalizedError {
        case badHost
        case unauthorized
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .badHost: return "That Canvas address doesn't look right."
            case .unauthorized: return "Canvas rejected the token. Generate a new one in Canvas → Account → Settings."
            case .server(let code): return "Canvas returned an error (\(code))."
            }
        }
    }

    // MARK: - Planner items

    /// Everything on your Canvas planner between today and `days` ahead:
    /// assignments, quizzes, discussions, calendar events, planner notes.
    static func fetchPlannerItems(credentials: Credentials, days: Int = 21) async throws -> [AgendaItem] {
        guard let base = credentials.baseURL else { throw CanvasError.badHost }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        var components = URLComponents(url: base.appendingPathComponent("api/v1/planner/items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: isoFormatter.string(from: start)),
            URLQueryItem(name: "end_date", value: isoFormatter.string(from: end)),
            URLQueryItem(name: "per_page", value: "100")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(credentials.token.trimmingCharacters(in: .whitespacesAndNewlines))",
                         forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 25

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CanvasError.server(0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw CanvasError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw CanvasError.server(http.statusCode) }

        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return raw.compactMap { item(from: $0, base: base) }
    }

    // MARK: - Parsing

    private static func item(from json: [String: Any], base: URL) -> AgendaItem? {
        let plannable = json["plannable"] as? [String: Any] ?? [:]

        // The date lives in different places depending on the item type.
        let dateString = (json["plannable_date"] as? String)
            ?? (plannable["due_at"] as? String)
            ?? (plannable["todo_date"] as? String)
            ?? (plannable["start_at"] as? String)
        guard let dateString, let date = parseDate(dateString) else { return nil }

        let title = (plannable["title"] as? String)
            ?? (plannable["name"] as? String)
            ?? "Untitled"

        let type = (json["plannable_type"] as? String) ?? "assignment"
        let plannableID = (json["plannable_id"] as? Int).map(String.init)
            ?? (plannable["id"] as? Int).map(String.init)
            ?? UUID().uuidString

        // `submissions` is an object for graded work, or `false` for things
        // that can't be submitted (calendar events, announcements, notes).
        var submitted = false
        var missing = false
        var graded = false
        if let submissions = json["submissions"] as? [String: Any] {
            submitted = (submissions["submitted"] as? Bool) ?? false
            missing = (submissions["missing"] as? Bool) ?? false
            graded = (submissions["graded"] as? Bool) ?? false
            if (submissions["excused"] as? Bool) == true { submitted = true }
        }

        var url: URL?
        if let path = json["html_url"] as? String {
            url = path.hasPrefix("http")
                ? URL(string: path)
                : URL(string: path, relativeTo: base)?.absoluteURL
        }

        var notes = (plannable["description"] as? String).map(stripHTML)
        if let text = notes, text.count > 900 { notes = String(text.prefix(900)) + "…" }

        let points = plannable["points_possible"] as? Double
        let isAllDay = (plannable["all_day"] as? Bool) ?? false

        var end: Date?
        if let endString = plannable["end_at"] as? String { end = parseDate(endString) }

        return AgendaItem(
            id: "canvas-api-\(type)-\(plannableID)",
            title: title,
            start: date,
            end: end,
            isAllDay: isAllDay,
            location: (plannable["location_name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            notes: (notes?.isEmpty == false) ? notes : nil,
            url: url,
            source: .canvas,
            courseName: (json["context_name"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            kind: AgendaItemKind(canvasType: type),
            isSubmitted: submitted,
            isMissing: missing && !submitted,
            isGraded: graded,
            pointsPossible: points
        )
    }

    private static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    private static func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
