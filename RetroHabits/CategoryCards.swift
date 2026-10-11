import SwiftUI

/// "Where it went": one card per spending category this week, side by side.
struct CategoryCards: View {
    @ObservedObject private var money = MoneyStore.shared

    var body: some View {
        if let s = money.summary, !s.byCategory.isEmpty {
            SectionTitle(title: "Where it went", symbol: "chart.pie")
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(s.byCategory) { total in
                        card(total, share: total.amount / max(s.spent, 0.01), isTop: total.id == s.byCategory.first?.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func card(_ total: AssistantService.MoneySummary.CategoryTotal, share: Double, isTop: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(total.category.capitalized, systemImage: SpendingList.symbol(total.category))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 8)
                if isTop && money.summary?.byCategory.count ?? 0 > 1 {
                    StatusPill(text: "Most", tone: .warn)
                }
            }
            Text(BudgetCard.money(total.amount))
                .font(.title.weight(.semibold))
                .monospacedDigit()
            Text("\(share.formatted(.percent.precision(.fractionLength(0)))) of this week")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 220, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22).fill(Palette.panel))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
