import WidgetKit
import SwiftUI

// MARK: - Timeline

struct HabitEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct HabitProvider: TimelineProvider {

    func placeholder(in context: Context) -> HabitEntry {
        HabitEntry(date: Date(), snapshot: HabitProvider.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (HabitEntry) -> Void) {
        let snapshot = WidgetBridge.loadSnapshot() ?? HabitProvider.sample
        completion(HabitEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HabitEntry>) -> Void) {
        let snapshot = WidgetBridge.loadSnapshot() ?? WidgetSnapshot()
        let entry = HabitEntry(date: Date(), snapshot: snapshot)
        // Refresh on the hour — the app also pushes updates when data changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    static let sample: WidgetSnapshot = {
        var snapshot = WidgetSnapshot()
        snapshot.habits = [
            .init(id: "1", name: "Read 20 min", icon: "📚", done: true, streak: 12),
            .init(id: "2", name: "Workout", icon: "💪", done: false, streak: 4),
            .init(id: "3", name: "Drink water", icon: "💧", done: false, streak: 30)
        ]
        snapshot.events = [
            .init(id: "e1", title: "Lab Report 3", start: Date().addingTimeInterval(7200),
                  isAllDay: false, courseName: "CHEM 1331", isSubmitted: false)
        ]
        snapshot.doneToday = 1
        snapshot.totalToday = 3
        snapshot.xp = 820
        snapshot.rankTitle = "VIGILANTE"
        return snapshot
    }()
}

// MARK: - Comic styling (widget-local copy)

private enum W {
    static let paper = Color(red: 1.00, green: 0.96, blue: 0.86)
    static let ink = Color.black
    static let red = Color(red: 0.89, green: 0.12, blue: 0.15)
    static let yellow = Color(red: 1.00, green: 0.80, blue: 0.00)
    static let blue = Color(red: 0.00, green: 0.45, blue: 0.85)

    static func bangers(_ size: CGFloat) -> Font { .custom("Bangers-Regular", size: size) }
    static func comic(_ size: CGFloat) -> Font { .custom("ComicNeue-Bold", size: size) }
}

// MARK: - Views

struct RetroHabitsWidgetEntryView: View {
    var entry: HabitEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .accessoryRectangular: lockScreenView
        default: mediumView
        }
    }

    // Small: progress ring-ish summary
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TODAY")
                    .font(W.bangers(16))
                    .foregroundStyle(W.red)
                Spacer()
                Text(entry.snapshot.rankTitle)
                    .font(W.bangers(11))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(W.blue))
            }

            Text("\(entry.snapshot.doneToday)/\(entry.snapshot.totalToday)")
                .font(W.bangers(38))
                .foregroundStyle(W.ink)
                .minimumScaleFactor(0.6)

            progressBar

            if let next = entry.snapshot.habits.first(where: { !$0.done }) {
                Text("\(next.icon) \(next.name)")
                    .font(W.comic(11))
                    .foregroundStyle(W.ink.opacity(0.75))
                    .lineLimit(1)
            } else if entry.snapshot.totalToday > 0 {
                Text("ALL DONE! 🎉")
                    .font(W.bangers(13))
                    .foregroundStyle(W.blue)
            }
        }
    }

    // Medium: habits on the left, next deadline on the right
    private var mediumView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text("HABITS")
                        .font(W.bangers(15))
                        .foregroundStyle(W.red)
                    Text("\(entry.snapshot.doneToday)/\(entry.snapshot.totalToday)")
                        .font(W.bangers(15))
                        .foregroundStyle(W.ink.opacity(0.6))
                }
                progressBar
                ForEach(entry.snapshot.habits.prefix(3)) { habit in
                    HStack(spacing: 5) {
                        Image(systemName: habit.done ? "checkmark.square.fill" : "square")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(habit.done ? W.red : W.ink.opacity(0.4))
                        Text(habit.name)
                            .font(W.comic(11))
                            .strikethrough(habit.done, color: W.red)
                            .foregroundStyle(habit.done ? W.ink.opacity(0.5) : W.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if habit.streak > 0 {
                            Text("🔥\(habit.streak)")
                                .font(W.bangers(11))
                                .foregroundStyle(W.ink.opacity(0.55))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(W.ink).frame(width: 2)

            VStack(alignment: .leading, spacing: 5) {
                Text("NEXT UP")
                    .font(W.bangers(15))
                    .foregroundStyle(W.blue)
                if entry.snapshot.events.isEmpty {
                    Text("Nothing scheduled.")
                        .font(W.comic(11))
                        .foregroundStyle(W.ink.opacity(0.6))
                } else {
                    ForEach(entry.snapshot.events.prefix(3)) { event in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                                .font(W.bangers(11))
                                .foregroundStyle(W.red)
                            Text(event.title)
                                .font(W.comic(11))
                                .foregroundStyle(event.isSubmitted ? W.ink.opacity(0.45) : W.ink)
                                .strikethrough(event.isSubmitted, color: W.blue)
                                .lineLimit(1)
                            if let course = event.courseName {
                                Text(course)
                                    .font(W.comic(9))
                                    .foregroundStyle(W.ink.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Lock screen
    private var lockScreenView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(entry.snapshot.doneToday)/\(entry.snapshot.totalToday) habits")
                .font(.headline)
            if let next = entry.snapshot.habits.first(where: { !$0.done }) {
                Text(next.name).font(.caption).lineLimit(1)
            } else if let event = entry.snapshot.events.first {
                Text(event.title).font(.caption).lineLimit(1)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white)
                Capsule()
                    .fill(W.red)
                    .frame(width: geo.size.width * progress)
            }
            .overlay(Capsule().stroke(W.ink, lineWidth: 2))
        }
        .frame(height: 11)
    }

    private var progress: Double {
        guard entry.snapshot.totalToday > 0 else { return 0 }
        return Double(entry.snapshot.doneToday) / Double(entry.snapshot.totalToday)
    }
}

// MARK: - Widget

struct RetroHabitsWidget: Widget {
    let kind = "RetroHabitsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HabitProvider()) { entry in
            RetroHabitsWidgetEntryView(entry: entry)
                .containerBackground(W.paper, for: .widget)
        }
        .configurationDisplayName("RetroHabits")
        .description("Today's habits and your next deadline.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct RetroHabitsWidgetBundle: WidgetBundle {
    var body: some Widget {
        RetroHabitsWidget()
    }
}
