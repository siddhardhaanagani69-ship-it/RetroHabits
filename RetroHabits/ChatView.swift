import SwiftUI

/// Talk to the assistant about plans, feelings, skills — anything. It knows your
/// agenda and recent logs, and remembers what you tell it across conversations.
struct ChatView: View {
    @Binding var turns: [AssistantService.Turn]
    @State private var draft = ""
    @State private var isSending = false
    @State private var error: String?
    @State private var inspecting: AssistantService.Turn?
    @FocusState private var inputFocused: Bool
    @StateObject private var dictation = Dictation()
    @StateObject private var voice = SpeechPlayer()
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
                            .buttonStyle(FilledButtonStyle(fill: speakReplies ? Palette.blue : Palette.fill,
                                                           textColor: speakReplies ? .white : Palette.blue))
                            .accessibilityLabel(speakReplies ? "Stop reading replies aloud" : "Read replies aloud")
                        }

                        if turns.isEmpty {
                            Card {
                                Text("Try: \"I'm stressed about my database class — what should I focus on this week?\"")
                                    .font(.bodyMedium(14))
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        ForEach(turns) { turn in
                            bubble(turn)
                            if turn.role == .assistant {
                                HStack(spacing: 8) {
                                    if !turn.memories.isEmpty { WhyButton { inspecting = turn } }
                                    Button {
                                        Task { await voice.toggle { try await AssistantService.speech(for: turn.text) } }
                                    } label: {
                                        Label("Listen", systemImage: "play.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Palette.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if isSending {
                            HStack(spacing: 8) {
                                ProgressView().tint(Palette.ink)
                                Text("Thinking…").font(.bodyMedium(13)).foregroundStyle(Palette.ink.opacity(0.6))
                            }
                        }
                        if let error = error ?? dictation.error {
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
                        RoundedRectangle(cornerRadius: 12).fill(mine ? Palette.blue : Palette.panel)
                        RoundedRectangle(cornerRadius: 12).stroke(Palette.hairline, lineWidth: 1)
                    }
                )
            if !mine { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await toggleMic() }
            } label: {
                Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(FilledButtonStyle(fill: dictation.isListening ? Palette.red : Palette.fill,
                                           textColor: dictation.isListening ? .white : Palette.blue))
            .disabled(isSending)
            .accessibilityLabel(dictation.isListening ? "Stop and send" : "Speak your question")

            TextField(dictation.isListening ? "Listening…" : "Ask anything…", text: $draft, axis: .vertical)
                .font(.bodyMedium(15))
                .foregroundStyle(Palette.ink)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(10)
                .background(Palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline, lineWidth: 1))
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .black))
            }
            .buttonStyle(FilledButtonStyle(fill: Palette.red, textColor: .white))
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        guard !message.isEmpty else { return }
        let history = turns
        draft = ""
        error = nil
        turns.append(.init(role: .user, text: message))
        isSending = true
        defer { isSending = false }
        do {
            let (reply, memories) = try await AssistantService.chat(message, history: history)
            turns.append(.init(role: .assistant, text: reply, memories: memories))
            if spoken || speakReplies {
                await voice.play { try await AssistantService.speech(for: reply) }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
