import SwiftUI

/// A small tinted capsule: "Optimal", "↑ +14 points", "Over by $8".
struct StatusPill: View {
    enum Tone {
        case good, warn, bad, neutral

        var color: Color {
            switch self {
            case .good: Palette.green
            case .warn: Palette.orange
            case .bad: Palette.red
            case .neutral: Palette.blue
            }
        }
    }

    let text: String
    var tone: Tone = .neutral
    var symbol: String?

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let symbol { Image(systemName: symbol) }
        }
        .labelStyle(PillLabelStyle(showsIcon: symbol != nil))
        .font(.subheadline.weight(.medium))
        .foregroundStyle(tone.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(tone.color.opacity(0.15)))
        .overlay(Capsule().strokeBorder(tone.color.opacity(0.35), lineWidth: 1))
    }

    private struct PillLabelStyle: LabelStyle {
        let showsIcon: Bool
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 4) {
                if showsIcon { configuration.icon }
                configuration.title
            }
        }
    }
}
