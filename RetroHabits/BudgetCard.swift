import SwiftUI

/// "$104.90 left this week" with progress, and the button to set the weekly budget.
struct BudgetCard: View {
    @ObservedObject private var money = MoneyStore.shared
    @State private var editing = false
    @State private var draft: Double?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if let s = money.summary, let budget = s.budget, let remaining = s.remaining {
                    Text(remaining >= 0 ? "\(Self.money(remaining)) left this week" : "\(Self.money(-remaining)) over this week")
                        .font(.title2.bold())
                        .foregroundStyle(remaining >= 0 ? Palette.ink : Palette.red)
                    ProgressCapsule(progress: min(1, s.spent / max(budget, 0.01)))
                    Text("Spent \(Self.money(s.spent)) of \(Self.money(budget)) · resets Monday")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Set a weekly budget")
                        .font(.title3.bold())
                    Text("Then Money, Ripple and Capture show what's left — and what a plan would cost.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let s = money.summary, s.spent > 0 {
                        Text("Spent \(Self.money(s.spent)) so far this week.")
                            .font(.subheadline)
                    }
                }
                Button(money.summary?.budget == nil ? "Set budget" : "Change budget", action: startEditing)
                    .buttonStyle(FilledButtonStyle())
            }
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
