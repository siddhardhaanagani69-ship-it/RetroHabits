import SwiftUI

/// The Money tab: budget left this week, quick logging, planned shift pay and
/// bills, the spending trend and this week's entries.
struct MoneyView: View {
    @ObservedObject private var money = MoneyStore.shared
    @EnvironmentObject private var routines: RoutineStore   // planned pay and bills follow routine edits

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Money", subtitle: "What you've spent this week, and what's coming.")
                BudgetCard()
                AddSpendingCard()
                PlannedMoneyCard()
                CategoryCards()
                SpendingTrendCard()
                SpendingList()
                if let error = money.error {
                    Text(error).font(.footnote).foregroundStyle(Palette.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .refreshable { await money.refresh() }
        .task { await money.refresh() }
    }
}
