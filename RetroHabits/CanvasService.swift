import Foundation

/// Fetches assignments and events from a Canvas calendar feed (.ics URL).
/// In Canvas: Calendar → "Calendar Feed" (bottom right) → copy the URL.
struct CanvasService {

    static func fetchItems(feedURLString: String) async throws -> [AgendaItem] {
        let trimmed = feedURLString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "webcal://", with: "https://")
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return ICSParser.parse(text)
    }
}
