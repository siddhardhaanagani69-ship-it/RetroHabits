import SwiftUI

/// One line on the Agenda home: what's left of this week's budget.
struct MoneyGlance: View {
    @ObservedObject private var money = MoneyStore.shared

    var body: some View {
        if let s = money.summary, s.budget != nil || s.spent > 0 {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if let remaining = s.remaining {
                            Text(remaining >= 0 ? "\(BudgetCard.money(remaining)) left this week" : "\(BudgetCard.money(-remaining)) over budget")
                                .font(.headline)
                                .foregroundStyle(remaining >= 0 ? Palette.ink : Palette.red)
                        }
                        Text("Spent \(BudgetCard.money(s.spent))" + (s.budget.map { " of \(BudgetCard.money($0))" } ?? " this week"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
