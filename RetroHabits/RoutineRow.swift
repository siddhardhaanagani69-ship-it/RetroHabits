import SwiftUI

/// A class or shift in the Routine tab: what, which days, when, and the reminder.
struct RoutineRow: View {
    let routine: Routine

    var body: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: routine.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(Palette.purple)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name)
                        .font(.bodyMedium(16))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.leading)
                    Text("\(days) · \(RoutineStore.time(routine))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let reminder {
                        Label(reminder, systemImage: "bell.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit \(routine.kind.label.lowercased())")
    }

    /// "Mon, Wed" in calendar order, or "Every day".
    private var days: String {
        guard routine.weekdays.count < 7 else { return "Every day" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return routine.weekdays.sorted().map { symbols[$0 - 1] }.formatted()
    }

    private var reminder: String? {
        switch routine.remindMinutesBefore {
        case nil: nil
        case 0?: "Reminder when it starts"
        case let m?: "Reminder \(m) min before"
        }
    }
}
