import SwiftUI

/// A big, soft crimson bubble behind the top of the screen. It drifts slowly on its
/// own and floats over to sit above whichever tab is selected. The circle is larger
/// than its gradient, so it fades to nothing with no edge.
struct GlowBackground: View {
    /// Where the bubble rests, 0 (left edge) to 1 (right edge).
    var x: CGFloat

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 560

    var body: some View {
        GeometryReader { geo in
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.78, green: 0.12, blue: 0.23).opacity(0.9),
                                              Color(red: 0.78, green: 0.12, blue: 0.23).opacity(0.35),
                                              .clear],
                                     center: .center, startRadius: 0, endRadius: size / 2))
                .frame(width: size, height: size)
                .position(x: x * geo.size.width, y: 60)
                .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: x)
                .phaseAnimator(reduceMotion ? [false] : [false, true]) { bubble, drifted in
                    bubble.offset(x: drifted ? 28 : -28, y: drifted ? 24 : -12)
                } animation: { _ in .easeInOut(duration: 7) }
        }
        .opacity(scheme == .dark ? 0.38 : 0.14)
        .frame(height: 420)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
