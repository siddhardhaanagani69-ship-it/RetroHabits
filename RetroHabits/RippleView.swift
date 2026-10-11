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
    @StateObject private var dictation = Dictation()
    @StateObject private var voice = SpeechPlayer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var plannedHabits: Int { habits.habits.filter(\.hasReminder).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputPanel
            if let result {
                graph(result).padding(.top, 14)
            }
        }
        .onChange(of: dictation.transcript) { _, heard in
            if dictation.isListening { draft = heard }   // live transcript in the field
        }
        .onAppear {
            // You paused: check the ripple of what was heard.
            dictation.onAutoStop = { heard in
                guard !heard.isEmpty, !isLoading else { return }
                draft = heard
                Task { await run() }
            }
        }
        .onDisappear {
            _ = dictation.stop()
            voice.stop()
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
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ripple Mode")
                    .font(.heading(22))
                    .foregroundStyle(Palette.red)
                Text("Say or type what changed, or ask “what if…”. I'll work out the rest and tell you what I'd do.")
                    .font(.bodyRegular(12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .bottom, spacing: 8) {
                    Button { Task { await toggleMic() } } label: {
                        Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(FilledButtonStyle(fill: dictation.isListening ? Palette.red : Palette.fill,
                                                   textColor: dictation.isListening ? .white : Palette.accent))
                    .disabled(isLoading)
                    .accessibilityLabel(dictation.isListening ? "Stop and check the ripple" : "Say what changed")
                    TextField(dictation.isListening ? "Listening…" : "My lab moved to Friday evening", text: $draft, axis: .vertical)
                        .font(.bodyRegular(16))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1...5)
                        .padding(.vertical, 11).padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Palette.paper, in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.hairline, lineWidth: 1))
                }
                if let micError = dictation.error {
                    Text(micError).font(.footnote).foregroundStyle(Palette.red)
                }
                Button {
                    Task { await run() }
                } label: {
                    Group {
                        if isLoading { ProgressView().tint(.white) } else { Label("See the Ripple", systemImage: "dot.radiowaves.right") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButtonStyle(fill: Palette.red, textColor: .white))
                .disabled(isLoading || draft.trimmingCharacters(in: .whitespaces).isEmpty)

                if plannedHabits == 0 {
                    Text("Tip: give a habit a reminder time (HABITS → tap it) so Ripple can check your planned sessions too.")
                        .font(.bodyRegular(11))
                        .foregroundStyle(Palette.ink.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error {
                    Text(error).font(.bodyMedium(13)).foregroundStyle(Palette.red)
                }
            }
        }
    }

    // MARK: Graph

    @ViewBuilder
    private func graph(_ r: AssistantService.RippleResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let o = r.verdict == nil ? 0 : 1   // later nodes shift down one when there's a verdict
            node(0) { changeNode(r) }
            if let verdict = r.verdict {
                connector(1)
                node(1) { verdictNode(verdict) }
            }

            if let clarify = r.clarify {
                connector(1 + o)
                node(1 + o) {
                    nodeCard(fill: Palette.yellow) {
                        Text("Need one more detail").font(.heading(16)).foregroundStyle(Palette.ink)
                        Text(clarify).font(.bodyMedium(14)).foregroundStyle(Palette.ink)
                    }
                }
            } else if r.conflicts.isEmpty {
                connector(1 + o)
                node(1 + o) {
                    nodeCard {
                        Text("No conflicts").font(.heading(18)).foregroundStyle(Palette.accent)
                        Text(r.change.kind == "cancel"
                             ? "That frees up time — nothing else needs to move."
                             : "Nothing in your calendar or planned habits overlaps.")
                            .font(.bodyMedium(14)).foregroundStyle(Palette.ink)
                    }
                }
            } else {
                ForEach(Array(r.conflicts.enumerated()), id: \.element.id) { index, conflict in
                    connector(index + 1 + o)
                    node(index + 1 + o) { conflictNode(conflict) }
                }
                connector(r.conflicts.count + 1 + o)
                node(r.conflicts.count + 1 + o) { planNode(r) }
            }
        }
    }

    /// Ripple's decision, in plain words, with a Listen button.
    private func verdictNode(_ verdict: String) -> some View {
        nodeCard {
            HStack {
                tag("What I'd do", Palette.accent)
                Spacer()
                Button {
                    Task {
                        if voice.state == .playing { voice.stop() }
                        else { await voice.play { try await AssistantService.speech(for: verdict) } }
                    }
                } label: {
                    HStack(spacing: 6) {
                        switch voice.state {
                        case .loading: ProgressView().controlSize(.small).tint(Palette.accent)
                        case .playing: Image(systemName: "stop.fill")
                        case .idle: Image(systemName: "play.fill")
                        }
                        Text(voice.state == .playing ? "Stop" : voice.state == .loading ? "Loading…" : "Listen")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(voice.state == .loading)
            }
            Text(verdict)
                .font(.bodyMedium(16))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let error = voice.error {
                Text(error).font(.footnote).foregroundStyle(Palette.red)
            }
        }
    }

    private func changeNode(_ r: AssistantService.RippleResult) -> some View {
        nodeCard(fill: r.hypothetical && !applied ? Palette.panel : Palette.yellow) {
            HStack {
                tag(r.hypothetical ? "What if" : "You said", r.hypothetical ? Palette.orange : Palette.accent)
                if !applied { tag("Hypothetical", Palette.ink.opacity(0.55)) } else { tag("Applied", Palette.red) }
            }
            Text(changeHeadline(r.change)).font(.heading(20)).foregroundStyle(Palette.ink)
            if let previous = r.change.previousStart {
                Text("Was \(Self.range(previous, r.change.previousEnd))")
                    .font(.bodyRegular(12)).foregroundStyle(Palette.ink.opacity(0.6))
            }
            ForEach(r.change.stated, id: \.self) { fact in
                Label(fact, systemImage: "quote.bubble.fill").font(.bodyMedium(12)).foregroundStyle(Palette.ink)
            }
            if let money = r.money {
                HStack(alignment: .top, spacing: 6) {
                    tag("PLANNED · NOT SPENT", Palette.purple)
                    Text(Self.costLine(money)).font(.bodyMedium(12)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(r.change.assumptions, id: \.self) { assumption in
                HStack(alignment: .top, spacing: 6) {
                    tag("Assumed", Palette.orange)
                    Text(assumption).font(.bodyMedium(12)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func conflictNode(_ c: AssistantService.RippleResult.Conflict) -> some View {
        nodeCard {
            HStack {
                tag(c.kind == "plan" ? "Your plan" : "Calendar", c.kind == "plan" ? Palette.red : Palette.accent)
                tag("Overlaps", Palette.ink.opacity(0.7))
            }
            Text(c.title).font(.heading(18)).foregroundStyle(Palette.ink)
            Text(Self.range(c.start, c.end)).font(.bodyMedium(13)).foregroundStyle(Palette.ink.opacity(0.7))

            if c.movable {
                if c.options.isEmpty {
                    Text("No free slot this week fits \(c.title).").font(.bodyMedium(12)).foregroundStyle(Palette.red)
                } else {
                    Text("Free slots this week").font(.heading(13)).foregroundStyle(Palette.ink.opacity(0.6))
                    FlowLayout(spacing: 6) {
                        ForEach(c.options, id: \.self) { option in
                            chip(Self.range(option.start, option.end), selected: choice[c.id] == option) {
                                choice[c.id] = option
                            }
                        }
                        chip("Keep as is", selected: choice[c.id] == nil) { choice[c.id] = nil }
                    }
                    .disabled(applied)
                }
            } else {
                Text("It's on your calendar, so the app won't move it — sort this one out with the organizer.")
                    .font(.bodyRegular(12)).foregroundStyle(Palette.ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func planNode(_ r: AssistantService.RippleResult) -> some View {
        let moves = r.conflicts.compactMap { c in choice[c.id].map { (c, $0) } }
        let fixed = r.conflicts.filter { !$0.movable }
        return nodeCard(fill: applied ? Palette.accent : Palette.yellow) {
            Text(applied ? "Plan updated" : "Revised plan").font(.heading(20)).foregroundStyle(Palette.red)
            if moves.isEmpty {
                Text("No planned sessions move.").font(.bodyMedium(13)).foregroundStyle(Palette.ink)
            }
            ForEach(moves, id: \.0.id) { conflict, option in
                Text("\(conflict.title): \(Self.short(conflict.start)) → \(Self.short(option.start))")
                    .font(.bodyMedium(14)).foregroundStyle(Palette.ink)
            }
            ForEach(fixed) { c in
                Text("Still overlapping: \(c.title) (\(Self.short(c.start)))")
                    .font(.bodyRegular(12)).foregroundStyle(Palette.ink.opacity(0.7))
            }
            Text("Moves change your plan only — nothing is marked done.")
                .font(.bodyRegular(11)).foregroundStyle(Palette.ink.opacity(0.55))

            if !applied {
                HStack(spacing: 10) {
                    Button { reject() } label: { Text("Reject").frame(maxWidth: .infinity) }
                        .buttonStyle(FilledButtonStyle())
                    Button { Task { await accept(moves) } } label: { Text("Accept").frame(maxWidth: .infinity) }
                        .buttonStyle(FilledButtonStyle(fill: Palette.red, textColor: .white))
                        .disabled(moves.isEmpty)
                }
            }
            if r.change.kind == "new", r.change.start != nil {
                Button { addingToCalendar = true } label: {
                    Label("Add \(r.change.title) to Calendar", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FilledButtonStyle(fill: Palette.accent, textColor: .white))
            }
        }
    }

    // MARK: Actions

    private func run() async {
        guard !isLoading else { return }   // the mic's auto-stop and a tap can both ask
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let r = try await AssistantService.ripple(draft, agenda: agenda.items, habits: habits.habits)
            applied = false
            shown = 0
            // Ripple's own picks; the first free slot when it didn't choose. -1 means leave it.
            choice = Dictionary(uniqueKeysWithValues: r.conflicts.compactMap { c in
                if let pick = r.picks?[c.id] {
                    return c.options.indices.contains(pick) ? (c.id, c.options[pick]) : nil
                }
                return c.options.first.map { (c.id, $0) }
            })
            result = r
            let steps = r.conflicts.count + 3
            if reduceMotion {
                shown = steps
            } else {
                // A quick top-to-bottom fade (about 0.2 s total) so the graph reads as a ripple.
                for step in 1...steps {
                    withAnimation(.easeOut(duration: 0.18)) { shown = step }
                    try? await Task.sleep(for: .milliseconds(40))
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// First tap listens; second tap checks the ripple of what was heard.
    private func toggleMic() async {
        if dictation.isListening {
            let heard = dictation.stop()
            if !heard.isEmpty { draft = heard }
            if !draft.trimmingCharacters(in: .whitespaces).isEmpty, !isLoading { await run() }
        } else {
            voice.stop()
            await dictation.start()
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
    }

    private func connector(_ index: Int) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.ink).frame(width: 3, height: 16)
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10)).foregroundStyle(Palette.ink)
        }
        .padding(.leading, 26)
        .opacity(shown >= index ? 1 : 0)
    }

    private func nodeCard<Content: View>(fill: Color = Palette.panel, @ViewBuilder _ content: () -> Content) -> some View {
        // Same card as everywhere else: a tint on the adaptive card color reads in dark mode too.
        Card(fill: fill) { VStack(alignment: .leading, spacing: 6) { content() } }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.heading(11))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
    }

    private func chip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.bodyMedium(12))
                .foregroundStyle(selected ? .white : Palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Palette.red : Palette.panel))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline, lineWidth: 1))
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

    /// "Costs $45.00 · would leave $105.00 of that week's $150.00".
    static func costLine(_ m: AssistantService.PlannedCost) -> String {
        let cost = "Costs \(BudgetCard.money(m.cost))"
        guard let budget = m.budget, let after = m.after else { return cost + " · set a weekly budget in Money to see if it fits" }
        return after >= 0
            ? cost + " · would leave \(BudgetCard.money(after)) of that week's \(BudgetCard.money(budget))"
            : cost + " · \(BudgetCard.money(-after)) over that week's \(BudgetCard.money(budget)) budget"
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
