import SwiftUI

/// "Coming up": bills due in the next week and pay from shifts still ahead, as a
/// timeline. Everything here is planned — nothing is counted as spent or earned.
struct PlannedMoneyCard: View {
    @ObservedObject private var money = MoneyStore.shared
    @EnvironmentObject private var routines: RoutineStore

    var body: some View {
        let steps = self.steps
        if !steps.isEmpty {
            SectionTitle(title: "Coming up", symbol: "flag")
            Card { Timeline(steps: steps) }
        }
    }

    private var steps: [Timeline.Step] {
        let pay = money.plannedShiftPay
        var steps = money.upcomingBills.map { item in
            Timeline.Step(
                id: "\(item.bill.id)-\(item.date.timeIntervalSince1970)",
                title: "\(item.bill.name) · \(item.bill.amount.map(BudgetCard.money) ?? "")",
                detail: Calendar.current.isDateInToday(item.date) ? "Due today" : "Due \(item.date.formatted(.dateTime.weekday(.wide)))",
                state: .later)
        }
        if pay.shifts > 0 {
            steps.append(Timeline.Step(
                id: "shift-pay",
                title: "Shift pay ≈ \(BudgetCard.money(pay.total))",
                detail: "\(pay.shifts) shift\(pay.shifts == 1 ? "" : "s") left this week · not earned yet",
                state: .later))
        }
        // The soonest item is the one to watch.
        if !steps.isEmpty { steps[0] = Timeline.Step(id: steps[0].id, title: steps[0].title, detail: steps[0].detail, state: .next) }
        return steps
    }
}
