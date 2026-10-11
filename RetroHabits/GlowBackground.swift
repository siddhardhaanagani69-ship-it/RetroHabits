import SwiftUI

/// The soft crimson glow across the top of a tab. Each tab's glow sits above its
/// place in the dock; when a tab appears, its glow starts where the previous tab's
/// was and glides over, so switching tabs looks like one glow following you.
/// Two radial gradients rather than a blur, so it costs nothing while scrolling.
struct GlowBackground: View {
    /// Where this tab's glow rests, 0 (left edge) to 1 (right edge).
    var x: CGFloat
    /// Where the previous tab's glow was.
    var from: CGFloat

    @State private var shown: CGFloat?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(colors: [Color(red: 0.86, green: 0.08, blue: 0.24), .clear],   // crimson
                               center: UnitPoint(x: 0.5, y: 0.3), startRadius: 0, endRadius: 260)
                RadialGradient(colors: [Color(red: 0.50, green: 0.02, blue: 0.14), .clear],   // deep maroon
                               center: UnitPoint(x: 0.25, y: 0.5), startRadius: 0, endRadius: 210)
            }
            .offset(x: ((shown ?? x) - 0.5) * geo.size.width)
        }
        .opacity(scheme == .dark ? 0.6 : 0.2)
        .frame(height: 480)
        .onAppear {
            guard !reduceMotion else { shown = x; return }
            shown = from
            withAnimation(.smooth(duration: 0.7)) { shown = x }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
