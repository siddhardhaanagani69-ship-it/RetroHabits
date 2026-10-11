import SwiftUI
import UIKit

/// The alerts list, shown as a segment inside the Agenda tab.
struct AlertsSection: View {
    @ObservedObject private var scheduler = NotificationScheduler.shared

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if scheduler.authorizationDenied {
                Card(fill: Palette.yellow) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notifications are off")
                            .font(.heading(20))
                            .foregroundStyle(Palette.red)
                        Text("Turn them on in iPhone Settings → RetroHabits → Notifications so alerts can reach you.")
                            .font(.bodyMedium(13))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            openSystemSettings()
                        } label: {
                            Text("Open Settings").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FilledButtonStyle(fill: Palette.red, textColor: .white))
                    }
                }
            }

            if scheduler.alerts.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("All quiet")
                            .font(.heading(24))
                            .foregroundStyle(Palette.accent)
                        Text("No alerts queued. Connect a source in Setup, then refresh — deadlines and events get their own alerts automatically.")
                            .font(.bodyMedium(14))
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Card(fill: Palette.yellow) {
                    HStack(spacing: 14) {
                        countBlock("\(count(of: .deadline))", "DEADLINE")
                        Divider().frame(height: 38)
                        countBlock("\(count(of: .event))", "EVENT")
                        Divider().frame(height: 38)
                        countBlock("\(count(of: .briefing) + count(of: .watch))", "DIGEST")
                    }
                    .frame(maxWidth: .infinity)
                }

                ForEach(groupedAlerts, id: \.day) { group in
                    SectionHeader(text: dayLabel(group.day))

                    ForEach(Array(group.alerts.enumerated()), id: \.element.id) { index, alert in
                        alertPanel(alert)
                    }
                }
            }

            Text("iOS doesn't let apps read other apps' notifications, so these are generated from your own Canvas and calendar data.")
                .font(.bodyRegular(11))
                .foregroundStyle(Palette.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .task { await scheduler.refreshAuthorizationStatus() }
    }

    // MARK: Pieces

    private func alertPanel(_ alert: ScheduledAlert) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Image(systemName: alert.kind.symbol)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(color(for: alert.kind))
                    Text(Self.timeFormatter.string(from: alert.fireDate))
                        .font(.heading(13))
                        .foregroundStyle(Palette.ink.opacity(0.7))
                }
                .frame(width: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.kind.label)
                        .font(.heading(12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color(for: alert.kind)))
                    Text(alert.title)
                        .font(.bodyMedium(15))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(alert.body)
                        .font(.bodyRegular(12))
                        .foregroundStyle(Palette.ink.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func countBlock(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.heading(28))
                .foregroundStyle(Palette.red)
            Text(label)
                .font(.heading(12))
                .foregroundStyle(Palette.ink.opacity(0.7))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func color(for kind: ScheduledAlert.Kind) -> Color {
        switch kind {
        case .deadline: return Palette.red
        case .event: return Palette.accent
        case .briefing: return Palette.orange
        case .watch: return Palette.ink.opacity(0.75)
        }
    }

    private func count(of kind: ScheduledAlert.Kind) -> Int {
        scheduler.alerts.filter { $0.kind == kind }.count
    }

    private var groupedAlerts: [(day: Date, alerts: [ScheduledAlert])] {
        let groups = Dictionary(grouping: scheduler.alerts) {
            Calendar.current.startOfDay(for: $0.fireDate)
        }
        return groups.keys.sorted().map { day in
            (day, groups[day]!.sorted { $0.fireDate < $1.fireDate })
        }
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInTomorrow(day) { return "Tomorrow" }
        return Self.dayFormatter.string(from: day).uppercased()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
