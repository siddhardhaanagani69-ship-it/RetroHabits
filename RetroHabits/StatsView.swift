import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: HabitStore
    @ObservedObject private var learn = LearnStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ComicHeader(title: "HERO STATS", subtitle: "Your legend, week by week.")

                rankPanel

                if store.habits.isEmpty {
                    ComicPanel(tilt: -0.8) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NO DATA YET!")
                                .font(.bangers(24))
                                .foregroundStyle(Comic.red)
                            Text("Add habits and start completing them — your track record shows up here.")
                                .font(.comic(14))
                                .foregroundStyle(Comic.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    ComicPanel(fill: Comic.yellow) {
                        HStack(spacing: 12) {
                            statBlock(value: "\(store.habits.count)", label: "HABITS")
                            Rectangle().fill(Comic.ink).frame(width: 2, height: 40)
                            statBlock(value: "\(bestStreak)", label: "BEST RUN")
                            Rectangle().fill(Comic.ink).frame(width: 2, height: 40)
                            statBlock(value: "\(Gamification.totalCompletions(store.habits))", label: "DONE")
                            Rectangle().fill(Comic.ink).frame(width: 2, height: 40)
                            statBlock(value: "\(learn.studiedCount)", label: "STUDIED")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                sectionLabel("ACHIEVEMENTS", color: Comic.orange)
                achievementGrid

                if !store.habits.isEmpty {
                    sectionLabel("TRACK RECORD", color: Comic.blue)
                    ForEach(Array(store.habits.enumerated()), id: \.element.id) { index, habit in
                        ComicPanel(tilt: index.isMultiple(of: 2) ? 0.5 : -0.5) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("\(habit.icon) \(habit.name.uppercased())")
                                        .font(.comic(16))
                                        .foregroundStyle(Comic.ink)
                                        .lineLimit(2)
                                    Spacer(minLength: 8)
                                    Text("🔥\(habit.streak)")
                                        .font(.bangers(20))
                                        .foregroundStyle(Comic.red)
                                }
                                CompletionGrid(habit: habit)
                                Text("LAST 10 WEEKS · \(completionCount(habit)) COMPLETED · BEST \(habit.longestStreak)")
                                    .font(.bangers(13))
                                    .foregroundStyle(Comic.ink.opacity(0.6))
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

        return ComicPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        StarburstShape(points: 12, innerRatio: 0.68)
                            .fill(rank.color)
                        StarburstShape(points: 12, innerRatio: 0.68)
                            .stroke(Comic.ink, lineWidth: 2.5)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 62, height: 62)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(rank.title)
                            .font(.bangers(28))
                            .foregroundStyle(rank.color)
                            .shadow(color: Comic.ink, radius: 0, x: 1.5, y: 1.5)
                        Text("\(xp) XP")
                            .font(.comic(14))
                            .foregroundStyle(Comic.ink.opacity(0.7))
                    }
                    Spacer()
                }

                ComicProgressBar(progress: progress)

                if let next {
                    Text("\(next.threshold - xp) XP TO \(next.title)")
                        .font(.bangers(14))
                        .foregroundStyle(Comic.ink.opacity(0.6))
                } else {
                    Text("MAXIMUM RANK ACHIEVED")
                        .font(.bangers(14))
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
                            .fill(isUnlocked ? achievement.color : Comic.ink.opacity(0.12))
                        Circle()
                            .stroke(Comic.ink, lineWidth: 2.5)
                        Image(systemName: isUnlocked ? achievement.symbol : "lock.fill")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(isUnlocked ? .white : Comic.ink.opacity(0.35))
                    }
                    .frame(width: 52, height: 52)

                    Text(achievement.title)
                        .font(.bangers(13))
                        .foregroundStyle(isUnlocked ? Comic.ink : Comic.ink.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Text(achievement.detail)
                        .font(.comicLight(10))
                        .foregroundStyle(Comic.ink.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isUnlocked ? Color.white : Color.white.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Comic.ink, lineWidth: isUnlocked ? 2.5 : 1.5)
                )
            }
        }
    }

    private func sectionLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.bangers(22))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Comic.ink).offset(x: 3, y: 3)
                    RoundedRectangle(cornerRadius: 6).fill(color)
                    RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 2)
                }
            )
            .padding(.top, 6)
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.bangers(24))
                .foregroundStyle(Comic.red)
            Text(label)
                .font(.bangers(11))
                .foregroundStyle(Comic.ink.opacity(0.7))
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
        ViewThatFits(in: .horizontal) {
            grid(cell: 18)
            grid(cell: 15)
            grid(cell: 12)
            grid(cell: 10)
        }
    }

    private func grid(cell: CGFloat) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<weeks, id: \.self) { week in
                VStack(spacing: spacing) {
                    ForEach(0..<7, id: \.self) { day in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(week: week, day: day))
                            .frame(width: cell, height: cell)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Comic.ink.opacity(0.5), lineWidth: 1)
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
            return Color.white.opacity(0.5)
        }
        if habit.isCompleted(on: date) { return Comic.red }
        if date >= calendar.startOfDay(for: habit.createdAt), habit.isScheduled(on: date) {
            return Comic.yellow.opacity(0.5)
        }
        return Color.white
    }
}
