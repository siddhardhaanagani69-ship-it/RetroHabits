import SwiftUI

/// Talk to the assistant about plans, feelings, skills — anything. It knows your
/// agenda and recent logs, and remembers what you tell it across conversations.
struct ChatView: View {
    @Binding var turns: [AssistantService.Turn]
    @State private var draft = ""
    /// The last message sent and when, so a double trigger (you tap Stop just as the
    /// mic stops by itself) can't send the same question twice.
    @State private var lastSent: (text: String, at: Date)?
    /// The full-screen editor for long messages.
    @State private var composing = false
    /// Matches the server's limit.
    private let maxLength = 8000
    @State private var isSending = false
    @State private var error: String?
    @State private var inspecting: AssistantService.Turn?
    @FocusState private var inputFocused: Bool
    @StateObject private var dictation = Dictation()
    @StateObject private var voice = SpeechPlayer()
    /// Which reply the player is on, so only that reply's button shows loading / Stop.
    @State private var speakingTurn: AssistantService.Turn.ID?
    /// Read every reply aloud, not just replies to spoken questions.
    @AppStorage("ask_speaks_replies") private var speakReplies = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            ScreenHeader(title: "Ask", subtitle: "Type or tap the mic — plans, feelings, skills.")
                            Button { speakReplies.toggle() } label: {
                                Image(systemName: speakReplies ? "speaker.wave.2.fill" : "speaker.slash")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .buttonStyle(FilledButtonStyle(fill: speakReplies ? Palette.accent : Palette.fill,
                                                           textColor: speakReplies ? .white : Palette.accent))
                            .accessibilityLabel(speakReplies ? "Stop reading replies aloud" : "Read replies aloud")
                        }

                        if turns.isEmpty {
                            Card {
                                Text("Try: \"I'm stressed about my database class — what should I focus on this week?\"")
                                    .font(.bodyRegular(14))
                                    .foregroundStyle(Palette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        ForEach(turns) { turn in
                            bubble(turn)
                            if turn.role == .assistant {
                                HStack(spacing: 8) {
                                    if !turn.memories.isEmpty { WhyButton { inspecting = turn } }
                                    listenButton(turn)
                                }
                            }
                        }

                        if isSending {
                            HStack(spacing: 8) {
                                ProgressView().tint(Palette.ink)
                                Text("Thinking…").font(.bodyMedium(13)).foregroundStyle(Palette.ink.opacity(0.6))
                            }
                        }
                        if let error = error ?? dictation.error ?? voice.error {
                            Text(error)
                                .font(.bodyMedium(13))
                                .foregroundStyle(Palette.red)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: turns.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom") }
                }
            }

            inputBar
        }
        .sheet(isPresented: $composing) { composer }
        .onAppear {
            // You paused: send what was heard, as if you'd tapped Stop.
            dictation.onAutoStop = { heard in
                guard !heard.isEmpty else { return }
                draft = heard
                Task { await send(spoken: true) }
            }
        }
        .onDisappear { _ = dictation.stop() }   // swiped to another tab
        .sheet(item: $inspecting) { turn in
            MemoryInspector(title: "What I drew on for that answer.", memories: turn.memories)
        }
    }

    private func bubble(_ turn: AssistantService.Turn) -> some View {
        let mine = turn.role == .user
        return HStack {
            if mine { Spacer(minLength: 40) }
            // Gemini replies use light markdown (**bold**); render it instead of showing asterisks.
            Text(LocalizedStringKey(turn.text))
                .font(.bodyMedium(15))
                .foregroundStyle(mine ? .white : Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(mine ? Palette.accent : Palette.panel)
                        RoundedRectangle(cornerRadius: 12).stroke(Palette.hairline, lineWidth: 1)
                    }
                )
            if !mine { Spacer(minLength: 40) }
        }
    }

    private func listenButton(_ turn: AssistantService.Turn) -> some View {
        let state = speakingTurn == turn.id ? voice.state : .idle
        return Button {
            Task { await listen(to: turn) }
        } label: {
            HStack(spacing: 6) {
                switch state {
                case .loading: ProgressView().controlSize(.small).tint(Palette.accent)
                case .playing: Image(systemName: "stop.fill")
                case .idle: Image(systemName: "play.fill")
                }
                Text(state == .playing ? "Stop" : state == .loading ? "Loading…" : "Listen")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.accent)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(state == .loading)
        .accessibilityLabel(state == .playing ? "Stop reading this reply" : "Read this reply aloud")
    }

    /// Plays a reply, or stops it if it's the one playing. Never touches the mic.
    private func listen(to turn: AssistantService.Turn) async {
        if speakingTurn == turn.id && voice.state == .playing { voice.stop(); return }
        if dictation.isListening { _ = dictation.stop() }
        speakingTurn = turn.id
        await voice.play { try await AssistantService.speech(for: turn.text) }
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.count <= maxLength
    }

    private var lengthLabel: some View {
        Text("\(draft.count) / \(maxLength)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(draft.count > maxLength ? Palette.red : Palette.muted)
    }

    /// Room to write or paste something long, then send it from here.
    private var composer: some View {
        NavigationStack {
            TextEditor(text: $draft)
                .font(.bodyRegular(17))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .background(Palette.paper)
                .navigationTitle("Message")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { composing = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            composing = false
                            Task { await send() }
                        }
                        .disabled(!canSend)
                    }
                    ToolbarItem(placement: .bottomBar) { lengthLabel }
                }
        }
    }

    private var inputBar: some View {
        VStack(alignment: .trailing, spacing: 4) {
        if draft.count > maxLength - 1000 { lengthLabel }
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                Task { await toggleMic() }
            } label: {
                Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(FilledButtonStyle(fill: dictation.isListening ? Palette.red : Palette.fill,
                                           textColor: dictation.isListening ? .white : Palette.accent))
            .disabled(isSending)
            .accessibilityLabel(dictation.isListening ? "Stop and send" : "Speak your question")

            HStack(alignment: .bottom, spacing: 4) {
                // Grows to 10 lines, then scrolls; the expand button opens a full-screen editor.
                TextField(dictation.isListening ? "Listening…" : "Ask anything…", text: $draft, axis: .vertical)
                    .font(.bodyRegular(16))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1...10)
                    .focused($inputFocused)
                    .padding(.vertical, 11)
                    .padding(.leading, 12)
                Button { composing = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 36, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Write a long message")
            }
            .frame(minHeight: 44)
            .background(Palette.panel, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.hairline, lineWidth: 1))
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .black))
            }
            .buttonStyle(FilledButtonStyle(fill: Palette.accent, textColor: .white))
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Palette.paper)
        .onChange(of: dictation.transcript) { _, heard in
            if dictation.isListening { draft = heard }   // live transcript in the field
        }
    }

    /// First tap listens; second tap sends what was heard and reads the answer aloud.
    private func toggleMic() async {
        // Your tap landed just after the mic stopped and sent by itself: don't start listening again.
        if !dictation.isListening, isSending, let lastSent, Date.now.timeIntervalSince(lastSent.at) < 2 { return }
        if dictation.isListening {
            let heard = dictation.stop()
            if !heard.isEmpty { draft = heard }
            await send(spoken: true)
        } else {
            voice.stop()   // don't transcribe our own voice
            inputFocused = false
            await dictation.start()
        }
    }

    private func send(spoken: Bool = false) async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !isSending else { return }
        if let lastSent, lastSent.text == message, Date.now.timeIntervalSince(lastSent.at) < 5 {
            draft = ""
            return
        }
        lastSent = (message, .now)
        let history = turns
        draft = ""
        error = nil
        turns.append(.init(role: .user, text: message))
        isSending = true
        defer { isSending = false }
        do {
            let (reply, memories) = try await AssistantService.chat(message, history: history)
            let answer = AssistantService.Turn(role: .assistant, text: reply, memories: memories)
            turns.append(answer)
            if spoken || speakReplies {
                speakingTurn = answer.id
                await voice.play { try await AssistantService.speech(for: reply) }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
