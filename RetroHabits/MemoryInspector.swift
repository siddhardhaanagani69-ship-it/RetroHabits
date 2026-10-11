import SwiftUI

/// "Why did you say that?" — the memories a recommendation was given, each one
/// correctable or deletable. Edits go to Backboard itself, then `onChange` re-runs
/// the recommendation so you can watch it update.
struct MemoryInspector: View {
    let title: String
    /// Records other than memories that fed the recommendation (logs, calendar…).
    var records: [String] = []
    @State var memories: [AssistantService.MemoryRef]
    var onChange: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var editing: String?
    @State private var draft = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: "Why?", subtitle: title)
                        .padding(.top, 20)

                    if !records.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Records it used").font(.heading(16)).foregroundStyle(Palette.accent)
                                ForEach(records, id: \.self) { Text("• \($0)").font(.bodyMedium(13)).foregroundStyle(Palette.ink) }
                            }
                        }
                    }

                    Text(memories.isEmpty ? "No memories were used" : "Memories it was given")
                        .font(.heading(18)).foregroundStyle(Palette.red)

                    ForEach(memories) { memory in
                        memoryCard(memory)
                    }

                    Text("Corrections and deletions change the stored memory itself — every later suggestion uses the fixed version.")
                        .font(.bodyRegular(11)).foregroundStyle(Palette.ink.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    if let error { Text(error).font(.bodyMedium(13)).foregroundStyle(Palette.red) }

                    Button { dismiss() } label: { Text("Done").frame(maxWidth: .infinity) }
                        .buttonStyle(FilledButtonStyle())
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func memoryCard(_ memory: AssistantService.MemoryRef) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                if memory.weak == true {
                    Text("Loose match — may not be relevant")
                        .font(.heading(11)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.orange))
                }
                if editing == memory.id {
                    TextField("What's actually true?", text: $draft, axis: .vertical)
                        .font(.bodyMedium(14)).foregroundStyle(Palette.ink)
                        .padding(8)
                        .background(Palette.paper)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hairline, lineWidth: 1))
                    HStack {
                        Button("Cancel") { editing = nil }.buttonStyle(FilledButtonStyle())
                        Button("Save") { Task { await save(memory) } }
                            .buttonStyle(FilledButtonStyle(fill: Palette.red, textColor: .white))
                            .disabled(busy || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    Text("“\(memory.content)”").font(.bodyMedium(14)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Correct") { draft = memory.content; editing = memory.id }
                            .buttonStyle(FilledButtonStyle())
                        Button("Forget") { Task { await forget(memory) } }
                            .buttonStyle(FilledButtonStyle())
                    }
                    .disabled(busy)
                }
            }
        }
    }

    private func save(_ memory: AssistantService.MemoryRef) async {
        busy = true
        defer { busy = false }
        do {
            let updated = try await AssistantService.correctMemory(memory.id, to: draft)
            if let i = memories.firstIndex(where: { $0.id == memory.id }) { memories[i].content = updated.content }
            editing = nil
            error = nil
            await onChange()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func forget(_ memory: AssistantService.MemoryRef) async {
        busy = true
        defer { busy = false }
        do {
            try await AssistantService.forgetMemory(memory.id)
            memories.removeAll { $0.id == memory.id }
            error = nil
            await onChange()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Small "Why?" pill that opens the inspector.
struct WhyButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Why?", systemImage: "magnifyingglass")
                .font(.heading(12))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Palette.panel))
                .overlay(Capsule().stroke(Palette.hairline, lineWidth: 1))
                .frame(minHeight: 44)   // the pill stays small; the tap area meets 44pt
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Everything the assistant remembers, from Setup — review, correct or forget any of it.
struct AllMemoriesSheet: View {
    @State private var memories: [AssistantService.MemoryRef]?
    @State private var failed = false

    var body: some View {
        Group {
            if let memories {
                MemoryInspector(title: "Everything I remember about you.", memories: memories)
            } else {
                ZStack {
                    Palette.paper.ignoresSafeArea()
                    if failed {
                        Text("Couldn't reach the assistant server.").font(.bodyMedium(14)).foregroundStyle(Palette.red)
                    } else {
                        ProgressView().tint(Palette.ink)
                    }
                }
            }
        }
        .task {
            do { memories = try await AssistantService.memories() } catch { failed = true }
        }
    }
}
