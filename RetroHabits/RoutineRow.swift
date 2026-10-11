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
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                    if let reminder {
                        Label(reminder, systemImage: "bell.fill")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
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

    /// "Mon and Wed · 10:00–11:15 AM", "Monthly on day 1 · $900.00", "Tue · 2–6 PM · $15.00/hr".
    private var detail: String {
        let money = { (value: Double) in value.formatted(.currency(code: Routine.currency)) }
        switch routine.kind {
        case .bill:
            let when = routine.monthlyDay.map { "Monthly on day \($0)" } ?? "Every \(days)"
            return [when, routine.amount.map(money)].compactMap { $0 }.joined(separator: " · ")
        default:
            return ["\(days) · \(RoutineStore.time(routine))", routine.hourlyRate.map { "\(money($0))/hr" }]
                .compactMap { $0 }.joined(separator: " · ")
        }
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
        case 0? where routine.kind == .bill: "Reminder on the due day"
        case 0?: "Reminder when it starts"
        case let m?: "Reminder \(m) min before"
        }
    }
}
