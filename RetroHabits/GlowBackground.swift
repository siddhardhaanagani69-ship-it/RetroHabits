import SwiftUI

/// The soft crimson glow behind a screen's header. Two radial gradients rather than
/// a blur, so it costs nothing while scrolling. Purely decorative.
///
/// It's attached to the scrolling content, which starts below the status bar, so it
/// is drawn taller than needed and shifted up: that carries the glow to the top edge
/// of the screen, behind the notch, instead of stopping in a hard line.
struct GlowBackground: View {
    @Environment(\.colorScheme) private var scheme

    /// How far above the content's top edge the glow reaches (covers any status bar).
    private let overhang: CGFloat = 220

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.86, green: 0.08, blue: 0.24), .clear],   // crimson
                           center: UnitPoint(x: 0.62, y: 0.42), startRadius: 0, endRadius: 260)
            RadialGradient(colors: [Color(red: 0.50, green: 0.02, blue: 0.14), .clear],   // deep maroon
                           center: UnitPoint(x: 0.25, y: 0.58), startRadius: 0, endRadius: 210)
        }
        .opacity(scheme == .dark ? 0.6 : 0.2)
        .frame(height: 380 + overhang)
        .offset(y: -overhang)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
