import SwiftUI

/// A screen's one big number: a small caps label, the value, an optional status
/// pill and an optional range bar ("$0 ━━━━━━──── $150").
struct HeroStat: View {
    let label: String
    let value: String
    var pill: StatusPill?
    var progress: Double?
    var low: String = ""
    var high: String = ""

    @ScaledMetric(relativeTo: .largeTitle) private var valueSize = 64.0

    var body: some View {
        VStack(spacing: 10) {
            Text(label.uppercased())
                .font(.footnote.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Palette.muted)
            Text(value)
                .font(.system(size: valueSize, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(Palette.ink)
            if let pill { pill }
            if let progress {
                HStack(spacing: 12) {
                    Text(low).font(.subheadline).foregroundStyle(Palette.muted)
                    ProgressCapsule(progress: progress)
                    Text(high).font(.subheadline).foregroundStyle(Palette.muted)
                }
                .padding(.top, 14)
                .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
