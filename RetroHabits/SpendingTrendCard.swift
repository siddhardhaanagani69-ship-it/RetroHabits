import SwiftUI
import Charts

/// Weekly spending for the last 8 weeks, stacked by category (Tiger Data time_bucket).
struct SpendingTrendCard: View {
    @ObservedObject private var money = MoneyStore.shared

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Last 8 weeks").font(.headline)
                if money.trend.isEmpty {
                    Text("Your weekly spending shows up here as you log it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(money.trend) { point in
                        BarMark(
                            x: .value("Week", point.weekStart, unit: .weekOfYear),
                            y: .value("Spent", point.amount)
                        )
                        .foregroundStyle(by: .value("Category", point.category.capitalized))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel { if let amount = value.as(Double.self) { Text(BudgetCard.money(amount)) } }
                        }
                    }
                    .frame(height: 200)
                    .accessibilityLabel("Weekly spending by category for the last 8 weeks")
                }
            }
        }
    }
}
