import SwiftUI

/// The soft blue glow behind a screen's header. Two radial gradients rather than a
/// blur, so it costs nothing while scrolling. Purely decorative.
struct GlowBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.16, green: 0.36, blue: 1.0), .clear],
                           center: UnitPoint(x: 0.62, y: 0.18), startRadius: 0, endRadius: 230)
            RadialGradient(colors: [Color(red: 0.36, green: 0.22, blue: 0.95), .clear],
                           center: UnitPoint(x: 0.28, y: 0.38), startRadius: 0, endRadius: 190)
        }
        .opacity(scheme == .dark ? 0.55 : 0.18)
        .frame(height: 380)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
