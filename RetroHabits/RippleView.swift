import SwiftUI
import EventKit
import EventKitUI

/// Ripple Mode: "if this changes, what else changes?"
///
/// One change (or a "what if…") → what it collides with → where displaced plans
/// could go → a revised plan you accept or reject. Every node says where its
/// facts came from, and nothing is applied until you press ACCEPT.
struct RippleView: View {
    @EnvironmentObject var agenda: AgendaStore
    @EnvironmentObject var habits: HabitStore
    /// Shared with Campus Capture's "Plan around it", which pre-fills it.
    @Binding var draft: String

    @State private var result: AssistantService.RippleResult?
    @State private var choice: [String: AssistantService.RippleResult.Option] = [:]
    @State private var isLoading = false
    @State private var error: String?
    @State private var applied = false
    @State private var shown = 0          // how many graph nodes have rippled in
    @State private var addingToCalendar = false

    private var plannedHabits: Int { habits.habits.filter(\.hasReminder).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputPanel
            if let result {
                graph(result).padding(.top, 14)
            }
        }
        .sheet(isPresented: $addingToCalendar) {
            if let change = result?.change, let start = change.start {
                EventEditor(title: change.title, start: start, end: change.end ?? start.addingTimeInterval(3600))
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: Input

    private var inputPanel: some View {
        ComicPanel(tilt: -0.3) {
            VStack(alignment: .leading, spacing: 10) {
                Text("RIPPLE MODE")
                    .font(.bangers(22))
                    .foregroundStyle(Comic.red)
                Text("Tell me what changed — or ask “what if…”. Tap the keyboard mic to say it.")
                    .font(.comicLight(12))
                    .foregroundStyle(Comic.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                TextField("My lab moved to Friday evening", text: $draft, axis: .vertical)
                    .font(.comic(15))
                    .foregroundStyle(Comic.ink)
                    .lineLimit(1...3)
                    .padding(10)
                    .background(Comic.paper)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 2))
                Button {
                    Task { await run() }
                } label: {
                    Group {
                        if isLoading { ProgressView().tint(.white) } else { Label("SEE THE RIPPLE", systemImage: "dot.radiowaves.right") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))
                .disabled(isLoading || draft.trimmingCharacters(in: .whitespaces).isEmpty)

                if plannedHabits == 0 {
                    Text("Tip: give a habit a reminder time (HABITS → tap it) so Ripple can check your planned sessions too.")
                        .font(.comicLight(11))
                        .foregroundStyle(Comic.ink.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error).font(.comic(13)).foregroundStyle(Comic.red)
                }
            }
        }
    }

    // MARK: Graph

    @ViewBuilder
    private func graph(_ r: AssistantService.RippleResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            node(0) { changeNode(r) }

            if let clarify = r.clarify {
                connector(1)
                node(1) {
                    nodeCard(fill: Comic.yellow) {
                        Text("NEED ONE MORE DETAIL").font(.bangers(16)).foregroundStyle(Comic.ink)
                        Text(clarify).font(.comic(14)).foregroundStyle(Comic.ink)
                    }
                }
            } else if r.conflicts.isEmpty {
                connector(1)
                node(1) {
                    nodeCard {
                        Text("NO CONFLICTS").font(.bangers(18)).foregroundStyle(Comic.blue)
                        Text(r.change.kind == "cancel"
                             ? "That frees up time — nothing else needs to move."
                             : "Nothing in your calendar or planned habits overlaps.")
                            .font(.comic(14)).foregroundStyle(Comic.ink)
                    }
                }
            } else {
                ForEach(Array(r.conflicts.enumerated()), id: \.element.id) { index, conflict in
                    connector(index + 1)
                    node(index + 1) { conflictNode(conflict) }
                }
                connector(r.conflicts.count + 1)
                node(r.conflicts.count + 1) { planNode(r) }
            }
        }
    }

    private func changeNode(_ r: AssistantService.RippleResult) -> some View {
        nodeCard(fill: r.hypothetical && !applied ? Comic.panel : Comic.yellow.opacity(0.5)) {
            HStack {
                tag(r.hypothetical ? "WHAT IF" : "YOU SAID", r.hypothetical ? Comic.orange : Comic.blue)
                if !applied { tag("HYPOTHETICAL", Comic.ink.opacity(0.55)) } else { tag("APPLIED", Comic.red) }
            }
            Text(changeHeadline(r.change)).font(.bangers(20)).foregroundStyle(Comic.ink)
            if let previous = r.change.previousStart {
                Text("Was \(Self.range(previous, r.change.previousEnd))")
                    .font(.comicLight(12)).foregroundStyle(Comic.ink.opacity(0.6))
            }
            ForEach(r.change.stated, id: \.self) { fact in
                Label(fact, systemImage: "quote.bubble.fill").font(.comic(12)).foregroundStyle(Comic.ink)
            }
            ForEach(r.change.assumptions, id: \.self) { assumption in
                HStack(alignment: .top, spacing: 6) {
                    tag("ASSUMED", Comic.orange)
                    Text(assumption).font(.comic(12)).foregroundStyle(Comic.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func conflictNode(_ c: AssistantService.RippleResult.Conflict) -> some View {
        nodeCard {
            HStack {
                tag(c.kind == "plan" ? "YOUR PLAN" : "CALENDAR", c.kind == "plan" ? Comic.red : Comic.blue)
                tag("OVERLAPS", Comic.ink.opacity(0.7))
            }
            Text(c.title.uppercased()).font(.bangers(18)).foregroundStyle(Comic.ink)
            Text(Self.range(c.start, c.end)).font(.comic(13)).foregroundStyle(Comic.ink.opacity(0.7))

            if c.movable {
                if c.options.isEmpty {
                    Text("No free slot this week fits \(c.title).").font(.comic(12)).foregroundStyle(Comic.red)
                } else {
                    Text("FREE SLOTS IN YOUR WEEK").font(.bangers(13)).foregroundStyle(Comic.ink.opacity(0.6))
                    FlowLayout(spacing: 6) {
                        ForEach(c.options, id: \.self) { option in
                            chip(Self.range(option.start, option.end), selected: choice[c.id] == option) {
                                choice[c.id] = option
                            }
                        }
                        chip("KEEP AS IS", selected: choice[c.id] == nil) { choice[c.id] = nil }
                    }
                    .disabled(applied)
                }
            } else {
                Text("It's on your calendar, so the app won't move it — sort this one out with the organizer.")
                    .font(.comicLight(12)).foregroundStyle(Comic.ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func planNode(_ r: AssistantService.RippleResult) -> some View {
        let moves = r.conflicts.compactMap { c in choice[c.id].map { (c, $0) } }
        let fixed = r.conflicts.filter { !$0.movable }
        return nodeCard(fill: Comic.yellow.opacity(applied ? 0.6 : 0.35)) {
            Text(applied ? "PLAN UPDATED" : "REVISED PLAN").font(.bangers(20)).foregroundStyle(Comic.red)
            if moves.isEmpty {
                Text("No planned sessions move.").font(.comic(13)).foregroundStyle(Comic.ink)
            }
            ForEach(moves, id: \.0.id) { conflict, option in
                Text("\(conflict.title): \(Self.short(conflict.start)) → \(Self.short(option.start))")
                    .font(.comic(14)).foregroundStyle(Comic.ink)
            }
            ForEach(fixed) { c in
                Text("Still overlapping: \(c.title) (\(Self.short(c.start)))")
                    .font(.comicLight(12)).foregroundStyle(Comic.ink.opacity(0.7))
            }
            Text("Moves change your plan only — nothing is marked done.")
                .font(.comicLight(11)).foregroundStyle(Comic.ink.opacity(0.55))

            if !applied {
                HStack(spacing: 10) {
                    Button { reject() } label: { Text("REJECT").frame(maxWidth: .infinity) }
                        .buttonStyle(ComicButtonStyle(fill: .white))
                    Button { Task { await accept(moves) } } label: { Text("ACCEPT").frame(maxWidth: .infinity) }
                        .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))
                        .disabled(moves.isEmpty)
                }
            }
            if r.change.kind == "new", r.change.start != nil {
                Button { addingToCalendar = true } label: {
                    Label("ADD \(r.change.title.uppercased()) TO CALENDAR", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ComicButtonStyle(fill: Comic.blue, textColor: .white))
            }
        }
    }

    // MARK: Actions

    private func run() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let r = try await AssistantService.ripple(draft, agenda: agenda.items, habits: habits.habits)
            applied = false
            shown = 0
            choice = Dictionary(uniqueKeysWithValues: r.conflicts.compactMap { c in
                c.options.first.map { (c.id, $0) }
            })
            withAnimation { result = r }
            for step in 1...(r.conflicts.count + 2) {   // ripple the nodes in one by one
                try? await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { shown = step }
            }
        } catch {
            self.error = "Couldn't reach the assistant server. Is it running?"
        }
    }

    private func accept(_ moves: [(AssistantService.RippleResult.Conflict, AssistantService.RippleResult.Option)]) async {
        for (conflict, option) in moves {
            guard let id = conflict.planId.flatMap(UUID.init(uuidString:)), let day = conflict.originalDay else { continue }
            habits.applyMove(habitID: id, originalDay: day, to: option.start)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { applied = true }
    }

    private func reject() {
        withAnimation {
            result = nil
            choice = [:]
        }
    }

    // MARK: Pieces

    private func node<Content: View>(_ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(shown >= index ? 1 : 0)
            .offset(y: shown >= index ? 0 : 14)
    }

    private func connector(_ index: Int) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Comic.ink).frame(width: 3, height: 16)
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10)).foregroundStyle(Comic.ink)
        }
        .padding(.leading, 26)
        .opacity(shown >= index ? 1 : 0)
    }

    private func nodeCard<Content: View>(fill: Color = Comic.panel, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Comic.ink).offset(x: 3, y: 3)
                    RoundedRectangle(cornerRadius: 10).fill(fill)
                    RoundedRectangle(cornerRadius: 10).stroke(Comic.ink, lineWidth: 2.5)
                }
            )
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.bangers(11))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.comic(12))
                .foregroundStyle(selected ? .white : Comic.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Comic.red : Color.white))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func changeHeadline(_ c: AssistantService.RippleResult.Change) -> String {
        switch c.kind {
        case "cancel": return "\(c.title) — cancelled"
        default:
            guard let start = c.start else { return c.title }
            return "\(c.title) → \(Self.range(start, c.end))"
        }
    }

    private static let dayTime: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f
    }()
    private static let timeOnly: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    static func short(_ date: Date) -> String { dayTime.string(from: date) }

    static func range(_ start: Date, _ end: Date?) -> String {
        guard let end else { return dayTime.string(from: start) }
        return "\(dayTime.string(from: start))–\(timeOnly.string(from: end))"
    }
}

/// The system "new event" sheet, pre-filled. The user reviews and saves it themselves.
struct EventEditor: UIViewControllerRepresentable {
    let title: String
    let start: Date
    let end: Date
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
