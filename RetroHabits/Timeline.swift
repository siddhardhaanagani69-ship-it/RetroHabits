import SwiftUI

/// A vertical list of steps joined by a line: done (green check), next (blue
/// dot) and later (dashed clock).
struct Timeline: View {
    struct Step: Identifiable {
        enum State { case done, next, later }
        let id: String
        let title: String
        let detail: String
        let state: State
    }

    let steps: [Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        marker(step.state)
                        if step.id != steps.last?.id {
                            Rectangle().fill(Palette.hairline).frame(width: 2).frame(minHeight: 22)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title).font(.body).foregroundStyle(Palette.ink)
                        Text(step.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func marker(_ state: Step.State) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.caption.bold())
                .foregroundStyle(Palette.green)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Palette.green.opacity(0.15)))
                .overlay(Circle().strokeBorder(Palette.green.opacity(0.4), lineWidth: 1))
        case .next:
            Circle().fill(Palette.blue).frame(width: 12, height: 12)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Palette.blue.opacity(0.18)))
                .overlay(Circle().strokeBorder(Palette.blue, lineWidth: 1.5))
        case .later:
            Image(systemName: "clock")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
        }
    }
}
