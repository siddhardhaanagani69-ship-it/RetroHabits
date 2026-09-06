import Foundation

/// Pulls fresh AI-engineering material from public, no-API-key sources:
/// arXiv (new papers), Hacker News (industry discussion), and Hugging Face
/// daily papers (curated). Each refresh requests a random slice so you get
/// different material every pull rather than the same top results.
enum LearnFeedService {

    // MARK: - Public

    static func fetchAll(tracks: Set<LearnTrack>) async -> [LearnCard] {
        let wanted = tracks.isEmpty ? Set(LearnTrack.allCases) : tracks

        return await withTaskGroup(of: [LearnCard].self) { group in
            for track in wanted {
                group.addTask { await fetchArxiv(track: track) }
            }
            group.addTask { await fetchHackerNews() }
            group.addTask { await fetchHuggingFacePapers() }

            var collected: [LearnCard] = []
            for await batch in group { collected += batch }

            // De-duplicate by id, keep the first of each.
            var seen = Set<String>()
            return collected.filter { seen.insert($0.id).inserted }
        }
    }

    // MARK: - arXiv

    /// Documented, stable, no key. We rotate the `start` offset so each pull
    /// lands on a different page of recent papers.
    private static func fetchArxiv(track: LearnTrack) async -> [LearnCard] {
        let query: String
        switch track {
        case .llm:   query = "abs:\"large language model\""
        case .rag:   query = "abs:\"retrieval augmented generation\" OR abs:\"retrieval-augmented\""
        case .cloud: query = "abs:\"LLM inference\" OR abs:\"model serving\" OR abs:\"efficient inference\""
        case .nlp:   query = "cat:cs.CL"
        }

        var components = URLComponents(string: "https://export.arxiv.org/api/query")!
        components.queryItems = [
            URLQueryItem(name: "search_query", value: query),
            URLQueryItem(name: "sortBy", value: "submittedDate"),
            URLQueryItem(name: "sortOrder", value: "descending"),
            URLQueryItem(name: "start", value: String(Int.random(in: 0...60))),
            URLQueryItem(name: "max_results", value: "12")
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("RetroHabits/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return [] }

        let entries = ArxivParser.parse(data)
        return entries.compactMap { entry in
            guard !entry.title.isEmpty else { return nil }
            let authors = entry.authors.prefix(3).joined(separator: ", ")
            let extra = entry.authors.count > 3 ? " +\(entry.authors.count - 3)" : ""
            return LearnCard(
                id: "arxiv-\(entry.id)",
                track: track,
                visual: visual(for: entry.title + entry.summary, track: track),
                title: clean(entry.title),
                hook: authors.isEmpty ? "New on arXiv" : "\(authors)\(extra)",
                body: trim(clean(entry.summary), to: 1100),
                terms: entry.categories.prefix(4).map { $0 },
                action: "Read the full paper on arXiv",
                isLive: true,
                sourceLabel: "arXiv · \(entry.categories.first ?? "cs")",
                link: entry.link,
                publishedAt: entry.published
            )
        }
    }

    // MARK: - Hacker News

    /// Algolia's HN API — no key. Rotating the query keeps the feed varied.
    private static func fetchHackerNews() async -> [LearnCard] {
        let queries = [
            "LLM", "RAG", "vector database", "AI engineering", "inference",
            "fine-tuning", "embeddings", "GPU", "transformers", "prompt engineering",
            "AI agents", "machine learning infrastructure"
        ]
        let query = queries.randomElement() ?? "LLM"

        var components = URLComponents(string: "https://hn.algolia.com/api/v1/search_by_date")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "tags", value: "story"),
            URLQueryItem(name: "numericFilters", value: "points>20"),
            URLQueryItem(name: "hitsPerPage", value: "10"),
            URLQueryItem(name: "page", value: String(Int.random(in: 0...3)))
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = json["hits"] as? [[String: Any]] else { return [] }

        let formatter = ISO8601DateFormatter()
        let track = trackFor(query)

        return hits.compactMap { hit in
            guard let objectID = hit["objectID"] as? String,
                  let title = hit["title"] as? String, !title.isEmpty else { return nil }
            let points = (hit["points"] as? Int) ?? 0
            let comments = (hit["num_comments"] as? Int) ?? 0
            let author = (hit["author"] as? String) ?? "someone"
            let storyText = (hit["story_text"] as? String).map(stripHTML) ?? ""
            let link = (hit["url"] as? String).flatMap(URL.init(string:))
                ?? URL(string: "https://news.ycombinator.com/item?id=\(objectID)")

            var body = storyText
            if body.count < 80 {
                body = "\(points) points and \(comments) comments on Hacker News. Posted by \(author).\n\nOpen the link to read the discussion — the comments are usually where the real engineering detail lives."
            }

            return LearnCard(
                id: "hn-\(objectID)",
                track: track,
                visual: visual(for: title, track: track),
                title: clean(title),
                hook: "▲ \(points) · \(comments) comments",
                body: trim(body, to: 900),
                terms: [],
                action: "Read the thread on Hacker News",
                isLive: true,
                sourceLabel: "Hacker News",
                link: link,
                publishedAt: (hit["created_at"] as? String).flatMap { formatter.date(from: $0) }
            )
        }
    }

    // MARK: - Hugging Face daily papers

    private static func fetchHuggingFacePapers() async -> [LearnCard] {
        guard let url = URL(string: "https://huggingface.co/api/daily_papers?limit=25") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        return json.compactMap { entry in
            let paper = entry["paper"] as? [String: Any] ?? [:]
            guard let paperID = paper["id"] as? String,
                  let title = (paper["title"] as? String) ?? (entry["title"] as? String),
                  !title.isEmpty else { return nil }

            let summary = (paper["summary"] as? String) ?? ""
            let upvotes = (paper["upvotes"] as? Int) ?? 0
            let dateString = (entry["publishedAt"] as? String) ?? (paper["publishedAt"] as? String) ?? ""
            let published = withFraction.date(from: dateString) ?? plain.date(from: dateString)
            let track = trackFor(title + " " + summary)

            return LearnCard(
                id: "hf-\(paperID)",
                track: track,
                visual: visual(for: title + summary, track: track),
                title: clean(title),
                hook: upvotes > 0 ? "▲ \(upvotes) upvotes · curated pick" : "Curated daily pick",
                body: trim(clean(summary), to: 1100),
                terms: [],
                action: "Read the paper page on Hugging Face",
                isLive: true,
                sourceLabel: "HF Daily Papers",
                link: URL(string: "https://huggingface.co/papers/\(paperID)"),
                publishedAt: published
            )
        }
    }

    // MARK: - Helpers

    private static func trackFor(_ text: String) -> LearnTrack {
        let lower = text.lowercased()
        if lower.contains("retrieval") || lower.contains("rag ") || lower.contains("vector database")
            || lower.contains("embedding") || lower.contains("search") {
            return .rag
        }
        if lower.contains("inference") || lower.contains("serving") || lower.contains("gpu")
            || lower.contains("kubernetes") || lower.contains("deploy") || lower.contains("infrastructure")
            || lower.contains("latency") || lower.contains("throughput") || lower.contains("cost") {
            return .cloud
        }
        if lower.contains("tokeniz") || lower.contains("translation") || lower.contains("sentiment")
            || lower.contains("named entity") || lower.contains("linguistic") || lower.contains("corpus") {
            return .nlp
        }
        return .llm
    }

    private static func visual(for text: String, track: LearnTrack) -> LearnVisual {
        let lower = text.lowercased()
        if lower.contains("attention") || lower.contains("transformer") { return .attention }
        if lower.contains("embedding") || lower.contains("vector") { return .vectors }
        if lower.contains("scal") || lower.contains("benchmark") || lower.contains("performance") { return .curve }
        if lower.contains("graph") || lower.contains("agent") || lower.contains("network") { return .network }
        if lower.contains("token") { return .tokens }
        if lower.contains("cluster") || lower.contains("classif") { return .cluster }
        switch track {
        case .llm: return .stack
        case .rag: return .pipeline
        case .cloud: return .stack
        case .nlp: return .tokens
        }
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripHTML(_ text: String) -> String {
        clean(text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\""))
    }

    private static func trim(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        // Break on the last sentence end so it doesn't stop mid-word.
        if let lastStop = cut.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            return String(cut[...lastStop])
        }
        return String(cut) + "…"
    }
}

// MARK: - arXiv Atom parsing

struct ArxivEntry {
    var id: String = ""
    var title: String = ""
    var summary: String = ""
    var authors: [String] = []
    var categories: [String] = []
    var link: URL?
    var published: Date?
}

/// Minimal Atom parser for the arXiv API (which returns XML, not JSON).
final class ArxivParser: NSObject, XMLParserDelegate {

    static func parse(_ data: Data) -> [ArxivEntry] {
        let parser = ArxivParser()
        let xml = XMLParser(data: data)
        xml.delegate = parser
        xml.parse()
        return parser.entries
    }

    private var entries: [ArxivEntry] = []
    private var current: ArxivEntry?
    private var text = ""
    private var insideAuthor = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        text = ""
        switch elementName {
        case "entry":
            current = ArxivEntry()
        case "author":
            insideAuthor = true
        case "category":
            if let term = attributeDict["term"] { current?.categories.append(term) }
        case "link":
            if attributeDict["rel"] == "alternate", let href = attributeDict["href"] {
                current?.link = URL(string: href)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "id":
            // Entry ids look like http://arxiv.org/abs/2401.12345v1
            if current != nil, current?.id.isEmpty == true {
                current?.id = value.components(separatedBy: "/abs/").last ?? value
            }
        case "title":
            if current != nil, current?.title.isEmpty == true { current?.title = value }
        case "summary":
            current?.summary = value
        case "name":
            if insideAuthor, !value.isEmpty { current?.authors.append(value) }
        case "author":
            insideAuthor = false
        case "published":
            let formatter = ISO8601DateFormatter()
            current?.published = formatter.date(from: value)
        case "entry":
            if let entry = current, !entry.id.isEmpty { entries.append(entry) }
            current = nil
        default:
            break
        }
        text = ""
    }
}
