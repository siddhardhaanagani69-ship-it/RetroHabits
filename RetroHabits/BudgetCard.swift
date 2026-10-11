import SwiftUI

/// The Money tab's hero: what's left this week, a status pill and a $0–budget bar.
struct BudgetCard: View {
    @ObservedObject private var money = MoneyStore.shared
    @State private var editing = false
    @State private var draft: Double?

    var body: some View {
        VStack(spacing: 6) {
            if let s = money.summary, let budget = s.budget, let remaining = s.remaining {
                HeroStat(
                    label: remaining >= 0 ? "Left this week" : "Over this week",
                    value: Self.money(abs(remaining)),
                    pill: pill(spent: s.spent, budget: budget, remaining: remaining),
                    progress: s.spent / max(budget, 0.01),
                    low: Self.money(0),
                    high: Self.money(budget)
                )
            } else {
                HeroStat(label: "Spent this week", value: Self.money(money.summary?.spent ?? 0),
                         pill: StatusPill(text: "No weekly budget yet", tone: .neutral))
            }
            Button(money.summary?.budget == nil ? "Set weekly budget" : "Change budget", action: startEditing)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .alert("Weekly budget", isPresented: $editing) {
            TextField("Amount", value: $draft, format: .currency(code: Routine.currency))
                .keyboardType(.decimalPad)
            Button("Save", action: save)
            if money.summary?.budget != nil {
                Button("Remove budget", role: .destructive) { Task { await money.setBudget(nil) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How much you want to spend Monday to Sunday.")
        }
    }

    /// Says where the week stands in words as well as color.
    private func pill(spent: Double, budget: Double, remaining: Double) -> StatusPill {
        if remaining < 0 { return StatusPill(text: "Over by \(Self.money(-remaining))", tone: .bad, symbol: "exclamationmark.triangle.fill") }
        if remaining < budget * 0.2 { return StatusPill(text: "Running low · \(Self.money(spent)) spent", tone: .warn) }
        return StatusPill(text: "On track · \(Self.money(spent)) spent", tone: .good, symbol: "checkmark")
    }

    private func startEditing() {
        draft = money.summary?.budget
        editing = true
    }

    private func save() {
        guard let draft, draft > 0 else { return }
        Task { await money.setBudget(draft) }
    }

    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: Routine.currency))
    }
}
