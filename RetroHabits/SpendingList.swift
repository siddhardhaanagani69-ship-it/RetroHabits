import SwiftUI

/// This week's recorded spending, newest first. Hold an entry to delete it.
struct SpendingList: View {
    @ObservedObject private var money = MoneyStore.shared

    var body: some View {
        if let entries = money.summary?.entries, !entries.isEmpty {
            SectionTitle(title: "This week", symbol: "list.bullet")
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        row(entry)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    Task { await money.delete(entry) }
                                }
                            }
                        if entry.id != entries.last?.id { Divider() }
                    }
                }
            }
            Text("Press and hold an entry to delete it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    private func row(_ entry: AssistantService.Spend) -> some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(entry.category))
                .foregroundStyle(Palette.blue)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.merchant ?? entry.note?.capitalized ?? entry.category.capitalized)
                    .font(.body)
                Text([entry.category.capitalized, entry.ts.formatted(.dateTime.weekday().hour().minute()),
                      entry.source == "receipt" ? "receipt" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(BudgetCard.money(entry.amount))
                .font(.body.monospacedDigit())
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Hold for options")
    }

    static func symbol(_ category: String) -> String {
        switch category {
        case "food": "fork.knife"
        case "groceries": "cart.fill"
        case "transport": "bus.fill"
        case "shopping": "bag.fill"
        case "entertainment": "ticket.fill"
        case "education": "book.fill"
        case "bills": "doc.text.fill"
        case "health": "cross.case.fill"
        default: "circle.fill"
        }
    }
}
