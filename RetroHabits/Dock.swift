import SwiftUI

/// The bottom dock: one button per tab, with a crimson highlight that slides to the
/// selected one. Paired with the paged TabView in ContentView, which handles swipes.
struct Dock: View {
    @Binding var selection: AppTab
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.dock, id: \.self) { tab in
                let selected = tab == selection
                Button {
                    withAnimation(.smooth(duration: 0.35)) { selection = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(height: 22)
                        Text(tab.rawValue)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? .white : Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Palette.accent)
                                .matchedGeometryEffect(id: "highlight", in: highlight)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Capsule().fill(Palette.panel))
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        .animation(.smooth(duration: 0.35), value: selection)
    }
}
