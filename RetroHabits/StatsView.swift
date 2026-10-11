import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: HabitStore
    @ObservedObject private var learn = LearnStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: "Stats", subtitle: "Your streaks, week by week.")

                rankPanel

                if store.habits.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No data yet")
                                .font(.heading(24))
                                .foregroundStyle(Palette.red)
                            Text("Add habits and start completing them — your track record shows up here.")
                                .font(.bodyMedium(14))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Card(fill: Palette.yellow) {
                        HStack(spacing: 12) {
                            statBlock(value: "\(store.habits.count)", label: "HABITS")
                            Divider().frame(height: 40)
                            statBlock(value: "\(bestStreak)", label: "BEST RUN")
                            Divider().frame(height: 40)
                            statBlock(value: "\(Gamification.totalCompletions(store.habits))", label: "DONE")
                            Divider().frame(height: 40)
                            statBlock(value: "\(learn.studiedCount)", label: "STUDIED")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                SectionHeader(text: "Achievements")
                achievementGrid

                if !store.habits.isEmpty {
                    SectionHeader(text: "Track Record")
                    ForEach(Array(store.habits.enumerated()), id: \.element.id) { index, habit in
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("\(habit.icon) \(habit.name)")
                                        .font(.bodyMedium(16))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(2)
                                    Spacer(minLength: 8)
                                    Text("🔥\(habit.streak)")
                                        .font(.heading(20))
                                        .foregroundStyle(Palette.red)
                                }
                                CompletionGrid(habit: habit)
                                Text("Last 10 weeks · \(completionCount(habit)) completed · best \(habit.longestStreak)")
                                    .font(.heading(13))
                                    .foregroundStyle(Palette.ink.opacity(0.6))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    // MARK: Rank

    private var rankPanel: some View {
        let xp = Gamification.totalXP(store.habits)
        let rank = HeroRank.rank(for: xp)
        let next = HeroRank.next(after: rank)
        let progress = Gamification.rankProgress(xp: xp)

        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle().fill(rank.color)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 62, height: 62)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(rank.title)
                            .font(.heading(28))
                            .foregroundStyle(rank.color)
                        Text("\(xp) XP")
                            .font(.bodyMedium(14))
                            .foregroundStyle(Palette.ink.opacity(0.7))
                    }
                    Spacer()
                }

                ProgressCapsule(progress: progress)

                if let next {
                    Text("\(next.threshold - xp) XP to \(next.title)")
                        .font(.heading(14))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                } else {
                    Text("Maximum rank achieved")
                        .font(.heading(14))
                        .foregroundStyle(rank.color)
                }
            }
        }
    }

    // MARK: Achievements

    private var achievementGrid: some View {
        let unlocked = Gamification.unlockedAchievements(store.habits)
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
            spacing: 10
        ) {
            ForEach(Achievement.all) { achievement in
                let isUnlocked = unlocked.contains(achievement.id)
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(isUnlocked ? achievement.color : Palette.ink.opacity(0.12))
                        Circle()
                            .stroke(Palette.hairline, lineWidth: 1)
                        Image(systemName: isUnlocked ? achievement.symbol : "lock.fill")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(isUnlocked ? .white : Palette.ink.opacity(0.35))
                    }
                    .frame(width: 52, height: 52)

                    Text(achievement.title)
                        .font(.heading(13))
                        .foregroundStyle(isUnlocked ? Palette.ink : Palette.ink.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Text(achievement.detail)
                        .font(.bodyRegular(10))
                        .foregroundStyle(Palette.ink.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isUnlocked ? Palette.panel : Palette.panel.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Palette.hairline, lineWidth: 1)
                )
            }
        }
    }


    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.heading(24))
                .foregroundStyle(Palette.red)
            Text(label)
                .font(.heading(11))
                .foregroundStyle(Palette.ink.opacity(0.7))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var bestStreak: Int {
        store.habits.map(\.longestStreak).max() ?? 0
    }

    private func completionCount(_ habit: Habit) -> Int {
        let calendar = Calendar.current
        var count = 0
        for offset in 0..<70 {
            if let day = calendar.date(byAdding: .day, value: -offset, to: Date()),
               habit.isCompleted(on: day) {
                count += 1
            }
        }
        return count
    }
}

/// Contribution-style grid: 10 weeks × 7 days.
struct CompletionGrid: View {
    let habit: Habit
    private let weeks = 10
    private let spacing: CGFloat = 3

    var body: some View {
        // Work out the 70 colors once; ViewThatFits may build every size below.
        let colors = (0..<weeks).map { week in (0..<7).map { day in color(week: week, day: day) } }
        ViewThatFits(in: .horizontal) {
            grid(cell: 18, colors: colors)
            grid(cell: 15, colors: colors)
            grid(cell: 12, colors: colors)
            grid(cell: 10, colors: colors)
        }
    }

    private func grid(cell: CGFloat, colors: [[Color]]) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<weeks, id: \.self) { week in
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colors[week][day])
                            .frame(width: cell, height: cell)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Palette.hairline, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .frame(height: 7 * cell + 6 * spacing)
    }

    private func color(week: Int, day: Int) -> Color {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today) // 1...7
        let daysBack = (weeks - 1 - week) * 7 + (todayWeekday - 1 - day)
        guard daysBack >= 0, let date = calendar.date(byAdding: .day, value: -daysBack, to: today) else {
            return Palette.panel.opacity(0.5)
        }
        if habit.isCompleted(on: date) { return Palette.red }
        if date >= calendar.startOfDay(for: habit.createdAt), habit.isScheduled(on: date) {
            return Palette.yellow.opacity(0.5)
        }
        return Palette.panel
    }
}
