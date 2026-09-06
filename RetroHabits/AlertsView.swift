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
                ComicPanel(fill: Comic.yellow) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOTIFICATIONS ARE OFF!")
                            .font(.bangers(20))
                            .foregroundStyle(Comic.red)
                        Text("Turn them on in iPhone Settings → RetroHabits → Notifications so alerts can reach you.")
                            .font(.comic(13))
                            .foregroundStyle(Comic.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            openSystemSettings()
                        } label: {
                            Text("OPEN SETTINGS").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(ComicButtonStyle(fill: Comic.red, textColor: .white))
                    }
                }
            }

            if scheduler.alerts.isEmpty {
                ComicPanel(tilt: -0.8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ALL QUIET…")
                            .font(.bangers(24))
                            .foregroundStyle(Comic.blue)
                        Text("No alerts queued. Connect a source in SETUP, then refresh — deadlines and events get their own alerts automatically.")
                            .font(.comic(14))
                            .foregroundStyle(Comic.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ComicPanel(fill: Comic.yellow) {
                    HStack(spacing: 14) {
                        countBlock("\(count(of: .deadline))", "DEADLINE")
                        Rectangle().fill(Comic.ink).frame(width: 2, height: 38)
                        countBlock("\(count(of: .event))", "EVENT")
                        Rectangle().fill(Comic.ink).frame(width: 2, height: 38)
                        countBlock("\(count(of: .briefing) + count(of: .watch))", "DIGEST")
                    }
                    .frame(maxWidth: .infinity)
                }

                ForEach(groupedAlerts, id: \.day) { group in
                    Text(dayLabel(group.day))
                        .font(.bangers(22))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 6).fill(Comic.ink).offset(x: 3, y: 3)
                                RoundedRectangle(cornerRadius: 6).fill(Comic.blue)
                                RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 2)
                            }
                        )
                        .padding(.top, 6)

                    ForEach(Array(group.alerts.enumerated()), id: \.element.id) { index, alert in
                        alertPanel(alert, tilt: index.isMultiple(of: 2) ? 0.6 : -0.6)
                    }
                }
            }

            Text("iOS doesn't let apps read other apps' notifications, so these are generated from your own Canvas and calendar data.")
                .font(.comicLight(11))
                .foregroundStyle(Comic.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .task { await scheduler.refreshAuthorizationStatus() }
    }

    // MARK: Pieces

    private func alertPanel(_ alert: ScheduledAlert, tilt: Double) -> some View {
        ComicPanel(tilt: tilt) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Image(systemName: alert.kind.symbol)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(color(for: alert.kind))
                    Text(Self.timeFormatter.string(from: alert.fireDate))
                        .font(.bangers(13))
                        .foregroundStyle(Comic.ink.opacity(0.7))
                }
                .frame(width: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.kind.label)
                        .font(.bangers(12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color(for: alert.kind)))
                    Text(alert.title)
                        .font(.comic(15))
                        .foregroundStyle(Comic.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(alert.body)
                        .font(.comicLight(12))
                        .foregroundStyle(Comic.ink.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func countBlock(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.bangers(28))
                .foregroundStyle(Comic.red)
            Text(label)
                .font(.bangers(12))
                .foregroundStyle(Comic.ink.opacity(0.7))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func color(for kind: ScheduledAlert.Kind) -> Color {
        switch kind {
        case .deadline: return Comic.red
        case .event: return Comic.blue
        case .briefing: return Comic.orange
        case .watch: return Comic.ink.opacity(0.75)
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
        if Calendar.current.isDateInToday(day) { return "TODAY" }
        if Calendar.current.isDateInTomorrow(day) { return "TOMORROW" }
        return Self.dayFormatter.string(from: day).uppercased()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
