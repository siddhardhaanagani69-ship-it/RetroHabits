import Foundation

/// Talks to the RetroHabits assistant backend (`backend/` in this repo).
enum AssistantService {

    /// The simulator reaches the Mac at localhost. A real phone needs the Mac's
    /// address on the same Wi-Fi, e.g. http://Sids-MacBook.local:8000 — set it in SETUP.
    static let defaultURL = "http://localhost:8000"

    static var baseURL: URL? {
        let text = UserDefaults.standard.string(forKey: "backend_url") ?? ""
        return URL(string: text.isEmpty ? defaultURL : text)
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
    static func summaries(for items: [AgendaItem]) async throws -> [String: Summary] {
        guard let base = baseURL else { throw URLError(.badURL) }
        var request = URLRequest(url: base.appendingPathComponent("summarize"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // First run summarizes everything in one Gemini call; later runs hit the cache.
        request.timeoutInterval = 60

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(items.map {
            Outgoing(id: $0.id, source: $0.source.rawValue, title: $0.title,
                     start: $0.start, notes: $0.notes, location: $0.location)
        })

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
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

    /// Uploads a recorded WAV note; the backend transcribes it, stores it and remembers it.
    static func log(audioAt fileURL: URL) async throws -> ParsedLog {
        guard let base = baseURL else { throw URLError(.badURL) }
        let boundary = UUID().uuidString
        var request = URLRequest(url: base.appendingPathComponent("log"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"note.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
        body += try Data(contentsOf: fileURL)
        body += Data("\r\n--\(boundary)--\r\n".utf8)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ParsedLog.self, from: data)
    }
}
