import SwiftUI

/// Money that's planned, not recorded: this week's shift pay and bills due soon.
struct PlannedMoneyCard: View {
    @ObservedObject private var money = MoneyStore.shared
    @EnvironmentObject private var routines: RoutineStore

    var body: some View {
        let pay = money.plannedShiftPay
        let bills = money.upcomingBills
        if pay.shifts > 0 || !bills.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Planned").font(.headline)
                    if pay.shifts > 0 {
                        Label {
                            Text("\(pay.shifts) shift\(pay.shifts == 1 ? "" : "s") left this week ≈ \(BudgetCard.money(pay.total)) — not earned yet")
                        } icon: {
                            Image(systemName: "briefcase.fill").foregroundStyle(Palette.purple)
                        }
                        .font(.subheadline)
                    }
                    ForEach(bills, id: \.bill.id) { item in
                        Label {
                            Text("\(item.bill.name) · \(item.bill.amount.map(BudgetCard.money) ?? "") · due \(item.date.formatted(.dateTime.weekday(.wide)))")
                        } icon: {
                            Image(systemName: "creditcard.fill").foregroundStyle(Palette.orange)
                        }
                        .font(.subheadline)
                    }
                    Text("Add shifts with pay and bills in Routine → Add Class or Shift.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
