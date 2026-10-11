import SwiftUI

/// A section heading with an icon, like "⚑ Next steps".
struct SectionTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(title).font(.title3.bold()).foregroundStyle(Palette.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Palette.muted)
        }
        .padding(.top, 14)
        .accessibilityAddTraits(.isHeader)
    }
}
