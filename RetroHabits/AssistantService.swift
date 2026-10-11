import Foundation

/// Talks to the RetroHabits assistant backend (`backend/` in this repo).
enum AssistantService {

    /// The deployed server. Override in SETUP to point at a local one
    /// (e.g. http://localhost:8000 from the simulator).
    static let defaultURL = "https://45-76-234-93.sslip.io"

    enum ServerError: LocalizedError {
        case unauthorized, quota, status(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Server token missing or wrong. Paste API_TOKEN in Setup → Assistant Server."
            case .quota: return "Gemini's free daily quota is used up. Try again later."
            case .status(let code): return "The assistant server returned an error (\(code))."
            }
        }
    }

    /// Turns a non-2xx response into an error that says what to fix.
    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw ServerError.unauthorized
        case 503: throw ServerError.quota
        default: throw ServerError.status(http.statusCode)
        }
    }

    static var baseURL: URL? {
        let text = UserDefaults.standard.string(forKey: "backend_url") ?? ""
        return URL(string: text.isEmpty ? defaultURL : text)
    }

    /// Shared secret the server checks (API_TOKEN in backend/.env). Kept in the Keychain.
    /// A token entered in Setup wins; otherwise the one baked in at build time
    /// (`xcodebuild … ASSISTANT_TOKEN=…`, read from backend/.env, never committed).
    static var token: String {
        get {
            let saved = Keychain.data(forKey: "backend_token").flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return saved.isEmpty ? (Bundle.main.object(forInfoDictionaryKey: "AssistantToken") as? String ?? "") : saved
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { Keychain.delete(forKey: "backend_token") }
            else { Keychain.set(Data(trimmed.utf8), forKey: "backend_token") }
        }
    }

    private static func authorize(_ request: inout URLRequest) {
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }

    struct Summary: Decodable {
        let id: String
        let summary: String
        let action: String
        let urgency: Int
        let course: String?
    }

    private struct Outgoing: Encodable {
        let id: String
        let source: String
        let title: String
        let start: Date
        let notes: String?
        let location: String?
    }

    /// Glance summaries keyed by item id.
    /// Adds the phone's time zone, so "due Monday 11:59 PM" means your Monday.
    private static func inLocalTime(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "tz", value: TimeZone.current.identifier)]
        return components?.url ?? url
    }

    static func summaries(for items: [AgendaItem]) async throws -> [String: Summary] {
        guard let base = baseURL else { throw URLError(.badURL) }
        var request = URLRequest(url: inLocalTime(base.appendingPathComponent("summarize")))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // First run summarizes everything in one Gemini call; later runs hit the cache.
        request.timeoutInterval = 60
        authorize(&request)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(items.map {
            Outgoing(id: $0.id, source: $0.source.rawValue, title: $0.title,
                     start: $0.start, notes: $0.notes, location: $0.location)
        })

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        let list = try JSONDecoder().decode([Summary].self, from: data)
        return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Voice log

    struct ParsedLog: Decodable {
        struct Exercise: Decodable {
            let name: String
            let sets: Int?
            let reps: Int?
            let weight: Double?
            let unit: String?
            let minutes: Double?

            /// "Squats 3×8 @ 135 lb" / "Bike 10 min"
            var line: String {
                var text = name
                if let sets, let reps { text += " \(sets)×\(reps)" }
                if let weight { text += " @ \(weight.formatted()) \(unit ?? "")" }
                if let minutes { text += " \(minutes.formatted()) min" }
                return text
            }
        }

        let kind: String
        let title: String
        let transcript: String
        let exercises: [Exercise]
        let mood: String?
    }

    // MARK: Ripple Mode

    struct RippleResult: Decodable {
        struct Change: Decodable {
            let kind: String            // move | new | cancel
            let title: String
            let start: Date?
            let end: Date?
            let previousStart: Date?
            let previousEnd: Date?
            let stated: [String]
            let assumptions: [String]
        }
        struct Option: Decodable, Hashable {
            let start: Date
            let end: Date
        }
        struct Conflict: Decodable, Identifiable {
            let id: String
            let title: String
            let start: Date
            let end: Date
            let kind: String            // plan | calendar
            let movable: Bool
            let options: [Option]
            let planId: String?
            let originalDay: String?
        }
        let hypothetical: Bool
        let clarify: String?
        let change: Change
        let conflicts: [Conflict]
        /// A stated cost and what it would leave of that week's budget. Planned, never spent.
        let money: PlannedCost?
    }

    struct PlannedCost: Decodable {
        let cost: Double
        let budget: Double?
        let remaining: Double?
        let after: Double?
    }

    /// Dates from the server come with or without fractional seconds.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = plain.date(from: text) ?? fractional.date(from: text) { return date }
            // Python sends microseconds (6 digits), which ISO8601DateFormatter rejects; drop them.
            let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
            if let date = plain.date(from: trimmed) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return decoder
    }()

    /// The next two weeks of agenda plus every habit with a planned time — what the
    /// server needs to compute conflicts. Shared by Ripple Mode and Campus Capture.
    struct Context: Encodable {
        struct AgendaOut: Encodable {
            let id: String, title: String, start: Date, end: Date?, allDay: Bool
        }
        struct PlanOut: Encodable {
            let id: String, name: String, weekdays: [Int], hour: Int, minute: Int, duration: Int
            let moves: [String: Date]
        }
        var change: String?
        let agenda: [AgendaOut]
        let plans: [PlanOut]
        let tz = TimeZone.current.identifier

        init(agenda: [AgendaItem], habits: [Habit], change: String? = nil) {
            let horizon = Date().addingTimeInterval(14 * 24 * 3600)
            self.change = change
            self.agenda = agenda.filter { $0.start < horizon }.map {
                AgendaOut(id: $0.id, title: $0.title, start: $0.start, end: $0.end, allDay: $0.isAllDay)
            }
            self.plans = habits.compactMap { habit in
                guard let hour = habit.reminderHour, let minute = habit.reminderMinute else { return nil }
                return PlanOut(id: habit.id.uuidString, name: habit.name, weekdays: habit.scheduledWeekdays.sorted(),
                               hour: hour, minute: minute, duration: habit.duration, moves: habit.moves ?? [:])
            }
        }

        func encoded() throws -> Data {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(self)
        }
    }

    /// What one change collides with. Nothing is applied until the user accepts.
    static func ripple(_ change: String, agenda: [AgendaItem], habits: [Habit]) async throws -> RippleResult {
        guard let base = baseURL else { throw URLError(.badURL) }
        var request = URLRequest(url: base.appendingPathComponent("ripple"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        authorize(&request)
        request.httpBody = try Context(agenda: agenda, habits: habits, change: change).encoded()

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        return try decoder.decode(RippleResult.self, from: data)
    }

    // MARK: Money

    struct MoneySummary: Decodable {
        struct CategoryTotal: Decodable, Identifiable {
            let category: String
            let amount: Double
            var id: String { category }
        }
        let weekStart: Date
        let budget: Double?
        let spent: Double
        let remaining: Double?
        let byCategory: [CategoryTotal]
        let entries: [Spend]
    }

    struct Spend: Decodable, Identifiable {
        let id: String
        let ts: Date
        let amount: Double
        let category: String
        let merchant: String?
        let note: String?
        let source: String
    }

    struct TrendPoint: Decodable, Identifiable {
        let weekStart: Date
        let category: String
        let amount: Double
        var id: String { "\(weekStart.timeIntervalSince1970)-\(category)" }
    }

    /// This week's budget, spending by category and every entry.
    static func money() async throws -> MoneySummary {
        try await get("money", query: ["tz": TimeZone.current.identifier])
    }

    /// Weekly spending per category for the last 8 weeks.
    static func moneyTrend() async throws -> [TrendPoint] {
        try await get("money/trend", query: ["tz": TimeZone.current.identifier, "weeks": "8"])
    }

    /// Records a purchase from a sentence ("$12 on lunch") or a receipt photo.
    static func addSpending(text: String? = nil, receiptJPEG: Data? = nil) async throws -> Spend {
        guard let base = baseURL else { throw URLError(.badURL) }
        let boundary = UUID().uuidString
        var request = URLRequest(url: base.appendingPathComponent("spend"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        authorize(&request)

        var body = Data()
        func field(_ name: String, _ value: String) {
            body += Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8)
        }
        field("tz", TimeZone.current.identifier)
        if let text { field("text", text) }
        if let receiptJPEG {
            body += Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"receipt.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
            body += receiptJPEG
            body += Data("\r\n".utf8)
        }
        body += Data("--\(boundary)--\r\n".utf8)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        // A 422 carries a question for the user ("How much was it?"); show it as-is.
        if let http = response as? HTTPURLResponse, http.statusCode == 422,
           let detail = try? JSONDecoder().decode([String: String].self, from: data)["detail"] {
            throw MoneyError.needsDetail(detail)
        }
        try check(response)
        return try decoder.decode(Spend.self, from: data)
    }

    enum MoneyError: LocalizedError {
        case needsDetail(String)
        var errorDescription: String? {
            switch self { case .needsDetail(let message): message }
        }
    }

    static func deleteSpending(_ id: String) async throws {
        struct Deleted: Decodable { let deleted: String }
        let _: Deleted = try await memoryRequest("spend/\(id)", method: "DELETE")
    }

    /// nil clears the budget.
    static func setBudget(_ weekly: Double?) async throws {
        guard let base = baseURL else { throw URLError(.badURL) }
        var request = URLRequest(url: base.appendingPathComponent("budget"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        authorize(&request)
        request.httpBody = try JSONEncoder().encode(["weekly": weekly])
        let (_, response) = try await URLSession.shared.data(for: request)
        try check(response)
    }

    private static func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        guard let base = baseURL,
              var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw URLError(.badURL) }
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: Campus Capture

    struct CaptureResult: Decodable {
        struct Event: Decodable {
            let isEvent: Bool
            let title: String
            let start: Date?
            let end: Date?
            let location: String?
            let cost: String?
            let organizer: String?
            let summary: String
            let missing: [String]
            let assumptions: [String]
        }
        struct Interest: Decodable {
            let memory: MemoryRef
            let why: String
        }
        let event: Event
        let conflicts: [RippleResult.Conflict]
        let interests: [Interest]
        let verdict: [String]
    }

    /// Flyer photo → event, calendar fit, shared interests, missing details.
    static func capture(imageJPEG: Data, agenda: [AgendaItem], habits: [Habit]) async throws -> CaptureResult {
        guard let base = baseURL else { throw URLError(.badURL) }
        let boundary = UUID().uuidString
        var request = URLRequest(url: base.appendingPathComponent("capture"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        authorize(&request)

        let context = try Context(agenda: agenda, habits: habits).encoded()
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"context\"\r\n\r\n".utf8)
        body += context
        body += Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"image\"; filename=\"flyer.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
        body += imageJPEG
        body += Data("\r\n--\(boundary)--\r\n".utf8)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        try check(response)
        return try decoder.decode(CaptureResult.self, from: data)
    }

    // MARK: Memory Inspector

    struct MemoryRef: Codable, Identifiable, Hashable {
        let id: String
        var content: String
        var score: Double?
        var weak: Bool?
    }

    static func memories() async throws -> [MemoryRef] {
        try await memoryRequest("memories", method: "GET")
    }

    /// Rewrites the memory in Backboard itself, so later recommendations use the correction.
    static func correctMemory(_ id: String, to content: String) async throws -> MemoryRef {
        try await memoryRequest("memories/\(id)", method: "PUT", body: ["content": content])
    }

    static func forgetMemory(_ id: String) async throws {
        struct Deleted: Decodable { let deleted: String }
        let _: Deleted = try await memoryRequest("memories/\(id)", method: "DELETE")
    }

    private static func memoryRequest<T: Decodable>(_ path: String, method: String,
                                                    body: [String: String]? = nil) async throws -> T {
        guard let base = baseURL else { throw URLError(.badURL) }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 30
        authorize(&request)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: History

    /// Records something that happened, so Ask can answer "when did I ...". Best effort:
    /// runs in the background and never holds up the UI.
    // ponytail: no offline queue; a record made with no connection is lost. Add one if that bites.
    static func recordHistory(ref: String, kind: String, title: String, detail: String? = nil, at: Date = .now) {
        var body = ["ref": ref, "kind": kind, "title": title, "at": at.ISO8601Format()]
        if let detail { body["detail"] = detail }
        Task {
            struct Recorded: Decodable { let ref: String }
            let _: Recorded? = try? await memoryRequest("history", method: "POST", body: body)
        }
    }

    static func deleteHistory(ref: String) {
        Task {
            struct Deleted: Decodable { let deleted: String }
            let _: Deleted? = try? await memoryRequest("history/\(ref)", method: "DELETE")
        }
    }

    // MARK: Spoken briefing

    /// MP3 of today's briefing, written by Gemini and read by ElevenLabs.
    static func briefingAudio() async throws -> Data {
        guard let base = baseURL,
              var components = URLComponents(url: base.appendingPathComponent("briefing"), resolvingAgainstBaseURL: false)
        else { throw URLError(.badURL) }
        components.queryItems = [URLQueryItem(name: "tz", value: TimeZone.current.identifier)]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        return data
    }

    /// A chat reply read aloud (MP3), same voice as the briefing.
    static func speech(for text: String) async throws -> Data {
        guard let base = baseURL else { throw URLError(.badURL) }
        var request = URLRequest(url: base.appendingPathComponent("speak"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        authorize(&request)
        request.httpBody = try JSONEncoder().encode(["text": text])
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        return data
    }

    // MARK: Inbox

    struct MailBrief: Decodable, Identifiable {
        let id: String
        let summary: String
        let action: String
        let urgency: Int
        let sender: String
        let subject: String
        let excerpt: String
        let link: URL?
        /// A deadline or meeting time the email states (nil if it doesn't).
        let due: Date?
        let dueEnd: Date?

        /// "Microsoft Teams <noreply@…>" → "Microsoft Teams"
        var senderName: String {
            let name = sender.components(separatedBy: "<").first?
                .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\""))) ?? ""
            return name.isEmpty ? sender : name
        }
    }

    /// Recent important email (incl. Teams notifications), summarized. Most urgent first.
    static func mail() async throws -> [MailBrief] {
        guard let base = baseURL else { throw URLError(.badURL) }
        var request = URLRequest(url: inLocalTime(base.appendingPathComponent("mail")))
        request.timeoutInterval = 90
        authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        return try decoder.decode([MailBrief].self, from: data)
            .sorted { $0.urgency > $1.urgency }
    }

    // MARK: Chat

    struct Turn: Codable, Identifiable {
        enum Role: String, Codable { case user, assistant }
        var id = UUID()
        let role: Role
        let text: String

        /// Memories the assistant was given for this reply (Memory Inspector). Not sent back.
        var memories: [MemoryRef] = []

        init(role: Role, text: String, memories: [MemoryRef] = []) {
            self.role = role
            self.text = text
            self.memories = memories
        }

        private enum CodingKeys: String, CodingKey { case role, text }
    }

    /// The assistant's reply. It sees your agenda, recent logs and long-term memory.
    static func chat(_ message: String, history: [Turn]) async throws -> (reply: String, memories: [MemoryRef]) {
        guard let base = baseURL else { throw URLError(.badURL) }
        struct Body: Encodable { let message: String; let history: [Turn]; let tz: String }
        struct Reply: Decodable { let reply: String; let memoriesUsed: [MemoryRef] }

        var request = URLRequest(url: base.appendingPathComponent("chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        authorize(&request)
        request.httpBody = try JSONEncoder().encode(
            Body(message: message, history: history, tz: TimeZone.current.identifier))

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        let reply = try decoder.decode(Reply.self, from: data)
        return (reply.reply, reply.memoriesUsed)
    }

    // MARK: Weekly recall

    struct Recall: Decodable {
        struct Session: Decodable {
            let title: String
            let exercises: [ParsedLog.Exercise]?
            let mood: String?
        }
        /// e.g. "Saturday, Oct 3" — nil when there's nothing on this weekday yet.
        let day: String?
        let logs: [Session]
        let suggestion: String?
        let memoriesUsed: [MemoryRef]
    }

    /// What you did on this weekday last time, and what to do today.
    static func recall() async throws -> Recall {
        guard let base = baseURL,
              var components = URLComponents(url: base.appendingPathComponent("recall"), resolvingAgainstBaseURL: false)
        else { throw URLError(.badURL) }
        components.queryItems = [URLQueryItem(name: "tz", value: TimeZone.current.identifier)]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        return try decoder.decode(Recall.self, from: data)
    }

    /// Uploads a recorded WAV note; the backend transcribes it, stores it and remembers it.
    static func log(audioAt fileURL: URL) async throws -> ParsedLog {
        guard let base = baseURL else { throw URLError(.badURL) }
        let boundary = UUID().uuidString
        var request = URLRequest(url: base.appendingPathComponent("log"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        authorize(&request)

        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"note.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
        body += try Data(contentsOf: fileURL)
        body += Data("\r\n--\(boundary)--\r\n".utf8)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        try check(response)
        return try JSONDecoder().decode(ParsedLog.self, from: data)
    }
}
