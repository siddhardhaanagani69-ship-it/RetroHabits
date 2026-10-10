import SwiftUI

/// "Last Saturday you did…" plus the assistant's suggestion for today.
/// Hidden until there's a past session on this weekday (or if the server is down).
struct RecallPanel: View {
    @State private var recall: AssistantService.Recall?

    var body: some View {
        Group {
            if let recall, let day = recall.day {
                ComicPanel(tilt: 0.5, fill: Comic.yellow) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LAST TIME · \(day.uppercased())")
                            .font(.bangers(18))
                            .foregroundStyle(Comic.blue)
                        ForEach(Array(recall.logs.enumerated()), id: \.offset) { _, session in
                            Text(session.title.uppercased())
                                .font(.bangers(20))
                                .foregroundStyle(Comic.ink)
                            ForEach(Array((session.exercises ?? []).enumerated()), id: \.offset) { _, exercise in
                                Text("• \(exercise.line)")
                                    .font(.comic(14))
                                    .foregroundStyle(Comic.ink)
                            }
                        }
                        if let suggestion = recall.suggestion {
                            Label(suggestion, systemImage: "sparkles")
                                .font(.comic(13))
                                .foregroundStyle(Comic.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                    }
                }
            }
        }
        .task { recall = try? await AssistantService.recall() }
    }
}
