import SwiftUI

// MARK: - Track

enum LearnTrack: String, Codable, CaseIterable, Identifiable {
    case llm = "LLM"
    case rag = "RAG"
    case cloud = "CLOUD"
    case nlp = "NLP"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .llm: return "LLMs"
        case .rag: return "RAG"
        case .cloud: return "CLOUD"
        case .nlp: return "NLP"
        }
    }

    var color: Color {
        switch self {
        case .llm: return Comic.red
        case .rag: return Comic.blue
        case .cloud: return Color(red: 0.0, green: 0.62, blue: 0.55)
        case .nlp: return Color(red: 0.55, green: 0.2, blue: 0.75)
        }
    }

    var symbol: String {
        switch self {
        case .llm: return "brain.head.profile"
        case .rag: return "magnifyingglass.circle.fill"
        case .cloud: return "cloud.fill"
        case .nlp: return "text.book.closed.fill"
        }
    }
}

/// The illustration drawn behind each card.
enum LearnVisual: String, Codable, CaseIterable {
    case pipeline      // boxes with arrows
    case attention     // grid of weighted cells
    case vectors       // scattered points in space
    case stack         // layered slabs
    case network       // nodes and edges
    case curve         // a scaling / loss curve
    case tokens        // text split into chunks
    case cluster       // grouped dots
}

// MARK: - Card

struct LearnCard: Identifiable, Codable, Equatable {
    var id: String
    var track: LearnTrack
    var visual: LearnVisual
    /// Big headline — the term or paper title.
    var title: String
    /// One-line hook or byline.
    var hook: String
    /// The explanation or abstract.
    var body: String
    /// Key terms worth knowing (empty for live cards).
    var terms: [String] = []
    /// A concrete thing to go do.
    var action: String = ""

    // Live-feed extras
    /// True for anything pulled from the internet, false for the built-in curriculum.
    var isLive: Bool = false
    /// e.g. "arXiv · cs.CL", "Hacker News", "HF Daily Papers"
    var sourceLabel: String?
    var link: URL?
    var publishedAt: Date?

    static func == (lhs: LearnCard, rhs: LearnCard) -> Bool { lhs.id == rhs.id }

    /// Stable across launches — `String.hashValue` is randomly seeded per
    /// process, which would redraw every illustration differently each time.
    var stableSeed: Int {
        id.unicodeScalars.reduce(into: 5_381) { result, scalar in
            result = result &* 33 &+ Int(scalar.value)
        }
    }

    var ageText: String? {
        guard let publishedAt else { return nil }
        let days = Calendar.current.dateComponents([.day], from: publishedAt, to: Date()).day ?? 0
        switch days {
        case ..<1: return "TODAY"
        case 1: return "YESTERDAY"
        case ..<7: return "\(days) DAYS AGO"
        case ..<30: return "\(days / 7)W AGO"
        default: return "\(days / 30)MO AGO"
        }
    }
}

// MARK: - Store

@MainActor
final class LearnStore: ObservableObject {

    static let shared = LearnStore()

    /// Fetched from the internet, newest first. Persisted so the feed works offline.
    @Published private(set) var liveCards: [LearnCard] = []
    @Published var selectedTracks: Set<LearnTrack> = Set(LearnTrack.allCases) {
        didSet { UserDefaults.standard.set(selectedTracks.map(\.rawValue), forKey: "learn_tracks") }
    }
    @Published private(set) var seenIDs: Set<String> = [] {
        didSet { UserDefaults.standard.set(Array(seenIDs.prefix(2000)), forKey: "learn_seen") }
    }
    @Published private(set) var savedIDs: Set<String> = [] {
        didSet { UserDefaults.standard.set(Array(savedIDs), forKey: "learn_saved") }
    }
    @Published var showSavedOnly = false
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var lastRefreshed: Date?
    /// Fresh items brought in by the last refresh — shown as a banner.
    @Published var newCardCount = 0

    /// The built-in crash course. Always available, even with no signal.
    let curriculum: [LearnCard] = LearnLibrary.all

    private let cacheLimit = 400

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("learn-cache.json")
    }

    private init() {
        seenIDs = Set(UserDefaults.standard.stringArray(forKey: "learn_seen") ?? [])
        savedIDs = Set(UserDefaults.standard.stringArray(forKey: "learn_saved") ?? [])
        if let stored = UserDefaults.standard.stringArray(forKey: "learn_tracks"), !stored.isEmpty {
            selectedTracks = Set(stored.compactMap(LearnTrack.init(rawValue:)))
        }
        if selectedTracks.isEmpty { selectedTracks = Set(LearnTrack.allCases) }
        loadCache()
    }

    // MARK: Feed

    /// What the scroll view shows: unseen live items first (the point of pulling
    /// to refresh), then unseen curriculum, then everything already read.
    var feed: [LearnCard] {
        var pool = liveCards + curriculum
        pool = pool.filter { selectedTracks.contains($0.track) }
        if showSavedOnly {
            return pool.filter { savedIDs.contains($0.id) }
        }

        let unseenLive = pool.filter { $0.isLive && !seenIDs.contains($0.id) }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        let unseenTaught = pool.filter { !$0.isLive && !seenIDs.contains($0.id) }
        let seen = pool.filter { seenIDs.contains($0.id) }
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }

        // Weave a teaching card in every few live ones so the feed stays useful
        // even when the research is over your head.
        var woven: [LearnCard] = []
        var taught = unseenTaught.makeIterator()
        for (index, card) in unseenLive.enumerated() {
            woven.append(card)
            if index % 3 == 2, let lesson = taught.next() {
                woven.append(lesson)
            }
        }
        while let lesson = taught.next() { woven.append(lesson) }
        return woven + seen
    }

    var unseenCount: Int {
        feed.filter { !seenIDs.contains($0.id) }.count
    }

    // MARK: Refresh

    func refresh() async {
        // Toolbar button, pull-to-refresh, .task and the end-of-feed button can
        // all fire at once — only let one through.
        guard !isLoading else { return }
        isLoading = true
        lastError = nil
        let fetched = await LearnFeedService.fetchAll(tracks: selectedTracks)
        isLoading = false

        guard !fetched.isEmpty else {
            if liveCards.isEmpty {
                lastError = "Couldn't reach the feeds. Showing the built-in course."
            }
            lastRefreshed = Date()
            return
        }

        let existing = Set(liveCards.map(\.id))
        let fresh = fetched.filter { !existing.contains($0.id) }
        newCardCount = fresh.filter { !seenIDs.contains($0.id) }.count

        // Newest first, capped so the cache doesn't grow forever.
        let merged = (fresh + liveCards)
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        liveCards = Array(merged.prefix(cacheLimit))
        lastRefreshed = Date()
        saveCache()
    }

    // MARK: Marks

    func markSeen(_ card: LearnCard) {
        guard !seenIDs.contains(card.id) else { return }
        seenIDs.insert(card.id)
    }

    func toggleSaved(_ card: LearnCard) {
        if savedIDs.contains(card.id) { savedIDs.remove(card.id) } else { savedIDs.insert(card.id) }
    }

    func isSaved(_ card: LearnCard) -> Bool { savedIDs.contains(card.id) }
    func isSeen(_ card: LearnCard) -> Bool { seenIDs.contains(card.id) }

    var studiedCount: Int { seenIDs.count }

    func progress(for track: LearnTrack) -> Double {
        let inTrack = curriculum.filter { $0.track == track }
        guard !inTrack.isEmpty else { return 0 }
        let done = inTrack.filter { seenIDs.contains($0.id) }.count
        return Double(done) / Double(inTrack.count)
    }

    func resetProgress() {
        seenIDs = []
    }

    // MARK: Cache

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cards = try? JSONDecoder().decode([LearnCard].self, from: data) else { return }
        liveCards = cards
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(liveCards) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
