import SwiftUI

/// Full-screen vertical paging feed — swipe up for the next topic.
///
/// Layout note: the scroll view deliberately does NOT ignore the safe area.
/// Each page is sized from the same GeometryReader that lays the scroll view
/// out, so page height == viewport height exactly. Ignoring the top safe area
/// here makes pages taller than the viewport, which clips cards and makes
/// paging drift a little further every swipe (very visible on Dynamic Island
/// phones like the iPhone 16, where the inset is ~59pt).
struct LearnView: View {
    @ObservedObject private var store = LearnStore.shared
    @State private var showingFilters = false
    @State private var currentID: String?
    /// A snapshot of the feed order. Marking a card seen reorders `store.feed`
    /// (unseen-first), which would yank the page out from under your thumb —
    /// so the visible order is only recomputed at deliberate moments.
    @State private var displayed: [LearnCard] = []

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Comic.paper

                if displayed.isEmpty {
                    emptyState
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    feedScroll(size: geo.size)
                }

                topBar
            }
        }
        .background(Comic.paper.ignoresSafeArea())
        .task {
            let stale = store.lastRefreshed.map { Date().timeIntervalSince($0) > 3600 } ?? true
            if stale { await store.refresh() }
            resyncOrder()
        }
        .onChange(of: store.liveCards.count) { _, _ in resyncOrder() }
        .onChange(of: store.selectedTracks) { _, _ in resyncOrder() }
        .onChange(of: store.showSavedOnly) { _, _ in resyncOrder() }
        .sheet(isPresented: $showingFilters) {
            LearnFilterSheet()
        }
    }

    private func resyncOrder() {
        displayed = store.feed
    }

    // MARK: Feed

    private func feedScroll(size: CGSize) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(displayed) { card in
                    LearnCardView(card: card, pageSize: size)
                        .id(card.id)
                        .frame(width: size.width, height: size.height)
                }

                EndOfFeedView()
                    .frame(width: size.width, height: size.height)
                    .id("end-of-feed")
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $currentID)
        .refreshable {
            await store.refresh()
            resyncOrder()
        }
        .onChange(of: currentID) { _, newID in
            // Only the card you actually landed on counts as read.
            guard let newID, let card = displayed.first(where: { $0.id == newID }) else { return }
            store.markSeen(card)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(Comic.ink.opacity(0.5))
            Text("NOTHING HERE")
                .font(.bangers(26))
                .foregroundStyle(Comic.red)
            Text(store.showSavedOnly
                 ? "You haven't saved any cards yet. Tap the bookmark on a card to keep it."
                 : "Turn a track back on to see cards.")
                .font(.comic(14))
                .foregroundStyle(Comic.ink)
                .multilineTextAlignment(.center)
            Button("FILTERS") { showingFilters = true }
                .buttonStyle(ComicButtonStyle())
        }
        .padding(32)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Text("LEARN")
                .font(.bangers(22))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Comic.red))
                .overlay(Capsule().stroke(Comic.ink, lineWidth: 2))

            if store.isLoading {
                ProgressView().tint(Comic.ink).scaleEffect(0.8)
            }

            Spacer(minLength: 4)

            if store.newCardCount > 0 {
                Text("+\(store.newCardCount)")
                    .font(.bangers(14))
                    .foregroundStyle(Comic.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Comic.yellow))
                    .overlay(Capsule().stroke(Comic.ink, lineWidth: 2))
            }

            circleButton("arrow.clockwise", tint: .white) {
                Task {
                    await store.refresh()
                    resyncOrder()
                }
            }

            circleButton("line.3.horizontal.decrease",
                         tint: store.showSavedOnly ? Comic.yellow : .white) {
                showingFilters = true
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private func circleButton(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(Comic.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint))
                .overlay(Circle().stroke(Comic.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - One card

struct LearnCardView: View {
    let card: LearnCard
    /// The exact page size, so every section can be laid out proportionally
    /// and the card is guaranteed to fit without clipping.
    let pageSize: CGSize

    @ObservedObject private var store = LearnStore.shared
    @Environment(\.openURL) private var openURL

    /// Leave room for the floating top bar so art isn't hidden behind it.
    private var artHeight: CGFloat {
        max(120, min(pageSize.height * 0.26, 210))
    }

    private var actionBarHeight: CGFloat { 62 }

    var body: some View {
        VStack(spacing: 0) {
            artPanel
            contentPanel
            actionBar
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .clipped()
    }

    // MARK: Art

    private var artPanel: some View {
        ZStack {
            card.track.color.opacity(0.32)
            LearnIllustration(
                visual: card.visual,
                color: card.track.color,
                seed: card.stableSeed
            )
        }
        .frame(height: artHeight)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            // Badges sit at the bottom of the art so they never collide with
            // the floating top bar.
            HStack(spacing: 6) {
                Label(card.track.title, systemImage: card.track.symbol)
                    .font(.bangers(14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(card.track.color))
                    .overlay(Capsule().stroke(Comic.ink, lineWidth: 2))

                if let age = card.ageText {
                    Text(age)
                        .font(.bangers(12))
                        .foregroundStyle(Comic.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Comic.yellow))
                        .overlay(Capsule().stroke(Comic.ink, lineWidth: 2))
                }

                if store.isSeen(card) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Comic.ink)
                        .padding(6)
                        .background(Circle().fill(.white))
                        .overlay(Circle().stroke(Comic.ink, lineWidth: 2))
                }
            }
            .padding(.leading, 14)
            .padding(.bottom, 10)
        }
        .overlay(Rectangle().frame(height: 3).foregroundStyle(Comic.ink), alignment: .bottom)
    }

    // MARK: Content

    private var contentPanel: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                Text(card.title.uppercased())
                    .font(.bangers(titleSize))
                    .foregroundStyle(Comic.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4)
                    .minimumScaleFactor(0.65)

                Text(card.hook)
                    .font(.comic(14))
                    .foregroundStyle(card.track.color)
                    .fixedSize(horizontal: false, vertical: true)

                Text(card.body)
                    .font(.comicLight(15))
                    .foregroundStyle(Comic.ink.opacity(0.85))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if !card.terms.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(card.terms, id: \.self) { term in
                            Text(term)
                                .font(.comic(12))
                                .foregroundStyle(Comic.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4).fill(Comic.yellow.opacity(0.6))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4).stroke(Comic.ink, lineWidth: 1.5)
                                )
                        }
                    }
                }

                if !card.action.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Comic.red)
                        Text(card.action)
                            .font(.comic(13))
                            .foregroundStyle(Comic.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Comic.yellow.opacity(0.45)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Comic.ink, lineWidth: 2))
                }

                if let source = card.sourceLabel {
                    Text(source.uppercased())
                        .font(.bangers(12))
                        .foregroundStyle(Comic.ink.opacity(0.5))
                }

                Color.clear.frame(height: 10)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: .infinity)
    }

    /// Long paper titles need to start smaller.
    private var titleSize: CGFloat {
        switch card.title.count {
        case ..<26: return 30
        case ..<50: return 25
        case ..<80: return 21
        default: return 18
        }
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    store.toggleSaved(card)
                }
            } label: {
                Image(systemName: store.isSaved(card) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(ComicButtonStyle(fill: store.isSaved(card) ? Comic.yellow : .white))

            if let link = card.link {
                Button {
                    openURL(link)
                } label: {
                    Label("OPEN SOURCE", systemImage: "arrow.up.right")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ComicButtonStyle(fill: card.track.color, textColor: .white))
            } else {
                Text("SWIPE UP ↑")
                    .font(.bangers(16))
                    .foregroundStyle(Comic.ink.opacity(0.45))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: actionBarHeight)
        .frame(maxWidth: .infinity)
        .background(
            Rectangle()
                .fill(Comic.paper)
                .overlay(Rectangle().frame(height: 2.5).foregroundStyle(Comic.ink), alignment: .top)
        )
    }
}

// MARK: - End marker

struct EndOfFeedView: View {
    @ObservedObject private var store = LearnStore.shared

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("THAT'S THE LOT!")
                .font(.bangers(32))
                .foregroundStyle(Comic.red)
                .shadow(color: Comic.ink, radius: 0, x: 2, y: 2)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("You've studied \(store.studiedCount) cards.")
                .font(.comic(16))
                .foregroundStyle(Comic.ink)
            Button {
                Task { await store.refresh() }
            } label: {
                Label("PULL IN NEW PAPERS", systemImage: "arrow.clockwise")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))
            .padding(.horizontal, 30)
            Text("Fresh research lands on arXiv every weekday.")
                .font(.comicLight(12))
                .foregroundStyle(Comic.ink.opacity(0.6))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Filters

struct LearnFilterSheet: View {
    @ObservedObject private var store = LearnStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Comic.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ComicHeader(title: "YOUR TRACKS", subtitle: "Pick what shows up in the feed.")
                        .padding(.top, 20)

                    ForEach(LearnTrack.allCases) { track in
                        trackRow(track)
                    }

                    ComicPanel {
                        Toggle(isOn: $store.showSavedOnly) {
                            Text("SAVED ONLY")
                                .font(.bangers(18))
                                .foregroundStyle(Comic.blue)
                        }
                        .tint(Comic.red)
                    }

                    Button {
                        store.resetProgress()
                    } label: {
                        Text("RESET READ HISTORY").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ComicButtonStyle(fill: .white))

                    Button {
                        dismiss()
                    } label: {
                        Text("DONE").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 16)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func trackRow(_ track: LearnTrack) -> some View {
        let isOn = store.selectedTracks.contains(track)
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                if isOn {
                    if store.selectedTracks.count > 1 { store.selectedTracks.remove(track) }
                } else {
                    store.selectedTracks.insert(track)
                }
            }
        } label: {
            ComicPanel(fill: isOn ? track.color.opacity(0.22) : .white) {
                HStack(spacing: 12) {
                    Image(systemName: track.symbol)
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(track.color)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.bangers(20))
                            .foregroundStyle(Comic.ink)
                        ComicProgressBar(progress: store.progress(for: track))
                            .frame(height: 12)
                        Text("\(Int(store.progress(for: track) * 100))% of the course read")
                            .font(.comicLight(11))
                            .foregroundStyle(Comic.ink.opacity(0.6))
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(isOn ? track.color : Comic.ink.opacity(0.3))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Wrapping tag layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
