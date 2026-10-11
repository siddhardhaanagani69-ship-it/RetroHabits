import SwiftUI

/// "Last Saturday you did…" plus the assistant's suggestion for today.
/// Hidden until there's a past session on this weekday (or if the server is down).
struct RecallPanel: View {
    @State private var recall: AssistantService.Recall?
    @State private var inspecting = false

    var body: some View {
        Group {
            if let recall, let day = recall.day {
                Card(fill: Palette.yellow) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last time · \(day)")
                            .font(.heading(18))
                            .foregroundStyle(Palette.blue)
                        ForEach(Array(recall.logs.enumerated()), id: \.offset) { _, session in
                            Text(session.title)
                                .font(.heading(20))
                                .foregroundStyle(Palette.ink)
                            ForEach(Array((session.exercises ?? []).enumerated()), id: \.offset) { _, exercise in
                                Text("• \(exercise.line)")
                                    .font(.bodyMedium(14))
                                    .foregroundStyle(Palette.ink)
                            }
                        }
                        if let suggestion = recall.suggestion {
                            Label(suggestion, systemImage: "sparkles")
                                .font(.bodyMedium(13))
                                .foregroundStyle(Palette.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                            WhyButton { inspecting = true }
                        }
                    }
                }
            }
        }
        .task { recall = try? await AssistantService.recall() }
        .sheet(isPresented: $inspecting) {
            if let recall {
                MemoryInspector(
                    title: "Why I suggested this for today.",
                    records: recall.logs.map { "Logged \(recall.day ?? ""): \($0.title)" },
                    memories: recall.memoriesUsed
                ) {
                    self.recall = try? await AssistantService.recall()   // watch the suggestion update
                }
            }
        }
    }
}
