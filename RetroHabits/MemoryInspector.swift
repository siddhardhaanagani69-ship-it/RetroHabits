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
            Comic.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ComicHeader(title: "WHY?", subtitle: title)
                        .padding(.top, 20)

                    if !records.isEmpty {
                        ComicPanel {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("RECORDS IT USED").font(.bangers(16)).foregroundStyle(Comic.blue)
                                ForEach(records, id: \.self) { Text("• \($0)").font(.comic(13)).foregroundStyle(Comic.ink) }
                            }
                        }
                    }

                    Text(memories.isEmpty ? "NO MEMORIES WERE USED" : "MEMORIES IT WAS GIVEN")
                        .font(.bangers(18)).foregroundStyle(Comic.red)

                    ForEach(memories) { memory in
                        memoryCard(memory)
                    }

                    Text("Corrections and deletions change the stored memory itself — every later suggestion uses the fixed version.")
                        .font(.comicLight(11)).foregroundStyle(Comic.ink.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    if let error { Text(error).font(.comic(13)).foregroundStyle(Comic.red) }

                    Button { dismiss() } label: { Text("DONE").frame(maxWidth: .infinity) }
                        .buttonStyle(ComicButtonStyle())
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func memoryCard(_ memory: AssistantService.MemoryRef) -> some View {
        ComicPanel {
            VStack(alignment: .leading, spacing: 8) {
                if memory.weak == true {
                    Text("LOOSE MATCH — MAY NOT BE RELEVANT")
                        .font(.bangers(11)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Comic.orange))
                }
                if editing == memory.id {
                    TextField("What's actually true?", text: $draft, axis: .vertical)
                        .font(.comic(14)).foregroundStyle(Comic.ink)
                        .padding(8)
                        .background(Comic.paper)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 2))
                    HStack {
                        Button("CANCEL") { editing = nil }.buttonStyle(ComicButtonStyle(fill: .white))
                        Button("SAVE") { Task { await save(memory) } }
                            .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))
                            .disabled(busy || draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    Text("“\(memory.content)”").font(.comic(14)).foregroundStyle(Comic.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("CORRECT") { draft = memory.content; editing = memory.id }
                            .buttonStyle(ComicButtonStyle(fill: Comic.yellow))
                        Button("FORGET") { Task { await forget(memory) } }
                            .buttonStyle(ComicButtonStyle(fill: .white))
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
            self.error = "Couldn't save the correction. Is the server reachable?"
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
            self.error = "Couldn't delete it. Is the server reachable?"
        }
    }
}

/// Small "WHY?" pill that opens the inspector.
struct WhyButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("WHY?", systemImage: "magnifyingglass")
                .font(.bangers(12))
                .foregroundStyle(Comic.ink)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.white))
                .overlay(Capsule().stroke(Comic.ink, lineWidth: 1.5))
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
                    Comic.paper.ignoresSafeArea()
                    if failed {
                        Text("Couldn't reach the assistant server.").font(.comic(14)).foregroundStyle(Comic.red)
                    } else {
                        ProgressView().tint(Comic.ink)
                    }
                }
            }
        }
        .task {
            do { memories = try await AssistantService.memories() } catch { failed = true }
        }
    }
}
