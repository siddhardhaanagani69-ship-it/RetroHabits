import SwiftUI

// MARK: - Card (inset-grouped style)

struct Card<Content: View>: View {
    /// A non-default fill becomes a light tint over the card, like iOS highlight rows.
    var fill: Color
    private let content: Content

    init(fill: Color = Palette.panel, @ViewBuilder content: () -> Content) {
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(fill == Palette.panel ? Color.clear : fill.opacity(0.16))
                    )
            )
    }
}

// MARK: - Screen header (large title)

struct ScreenHeader: View {
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Section header (grouped-list style)

struct SectionHeader: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 10)
            .padding(.leading, 4)
    }
}

// MARK: - Button style

/// iOS-style button: tinted gray by default (like `.bordered`), or a solid fill
/// with white text for the primary action.
struct FilledButtonStyle: ButtonStyle {
    var fill: Color = Palette.fill
    var textColor: Color = Palette.blue

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, fill: fill, textColor: textColor)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let fill: Color
        let textColor: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(textColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}

// MARK: - Source tag

struct SourceTag: View {
    var source: AgendaSource

    var body: some View {
        Text(source.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(source.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(source.tint.opacity(0.14)))
    }
}

// MARK: - Progress bar

struct ProgressCapsule: View {
    /// 0...1
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fill)
                Capsule()
                    .fill(Palette.blue)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
    }
}
