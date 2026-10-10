import SwiftUI

/// Talk to the assistant about plans, feelings, skills — anything. It knows your
/// agenda and recent logs, and remembers what you tell it across conversations.
struct ChatView: View {
    @Binding var turns: [AssistantService.Turn]
    @State private var draft = ""
    @State private var isSending = false
    @State private var error: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ComicHeader(title: "ASK HQ", subtitle: "Plans, feelings, skills — talk it out.")

                        if turns.isEmpty {
                            ComicPanel(tilt: -0.6) {
                                Text("Try: \"I'm stressed about my database class — what should I focus on this week?\"")
                                    .font(.comic(14))
                                    .foregroundStyle(Comic.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        ForEach(turns) { turn in
                            bubble(turn)
                        }

                        if isSending {
                            HStack(spacing: 8) {
                                ProgressView().tint(Comic.ink)
                                Text("Thinking…").font(.comic(13)).foregroundStyle(Comic.ink.opacity(0.6))
                            }
                        }
                        if let error {
                            Text(error)
                                .font(.comic(13))
                                .foregroundStyle(Comic.red)
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
    }

    private func bubble(_ turn: AssistantService.Turn) -> some View {
        let mine = turn.role == .user
        return HStack {
            if mine { Spacer(minLength: 40) }
            Text(turn.text)
                .font(.comic(15))
                .foregroundStyle(mine ? .white : Comic.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Comic.ink).offset(x: 3, y: 3)
                        RoundedRectangle(cornerRadius: 12).fill(mine ? Comic.blue : Color.white)
                        RoundedRectangle(cornerRadius: 12).stroke(Comic.ink, lineWidth: 2)
                    }
                )
            if !mine { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask anything…", text: $draft, axis: .vertical)
                .font(.comic(15))
                .foregroundStyle(Comic.ink)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(10)
                .background(Color.white)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Comic.ink, lineWidth: 2))
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .black))
            }
            .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Comic.paper)
    }

    private func send() async {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        let history = turns
        draft = ""
        error = nil
        turns.append(.init(role: .user, text: message))
        isSending = true
        defer { isSending = false }
        do {
            let reply = try await AssistantService.chat(message, history: history)
            turns.append(.init(role: .assistant, text: reply))
        } catch {
            self.error = "Couldn't reach the assistant server. Is it running?"
        }
    }
}
