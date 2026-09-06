import SwiftUI

// MARK: - Ranks

struct HeroRank: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let threshold: Int
    let color: Color

    static let all: [HeroRank] = [
        HeroRank(title: "ROOKIE",    threshold: 0,     color: Comic.ink.opacity(0.6)),
        HeroRank(title: "SIDEKICK",  threshold: 250,   color: Comic.blue),
        HeroRank(title: "VIGILANTE", threshold: 750,   color: Comic.orange),
        HeroRank(title: "HERO",      threshold: 1_500, color: Comic.red),
        HeroRank(title: "AVENGER",   threshold: 3_000, color: Color(red: 0.55, green: 0.2, blue: 0.75)),
        HeroRank(title: "LEGEND",    threshold: 6_000, color: Color(red: 0.85, green: 0.65, blue: 0.0)),
        HeroRank(title: "COSMIC",    threshold: 12_000, color: Color(red: 0.0, green: 0.65, blue: 0.55))
    ]

    static func rank(for xp: Int) -> HeroRank {
        all.last { xp >= $0.threshold } ?? all[0]
    }

    static func next(after rank: HeroRank) -> HeroRank? {
        guard let index = all.firstIndex(of: rank), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}

// MARK: - Achievements

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    /// Returns true when unlocked, given the player's habits.
    let isUnlocked: ([Habit]) -> Bool

    static let all: [Achievement] = [
        Achievement(
            id: "first-habit",
            title: "ORIGIN STORY",
            detail: "Create your first habit",
            symbol: "sparkles",
            color: Comic.blue,
            isUnlocked: { !$0.isEmpty }
        ),
        Achievement(
            id: "first-done",
            title: "FIRST BLOOD",
            detail: "Complete a habit once",
            symbol: "checkmark.seal.fill",
            color: Comic.red,
            isUnlocked: { $0.contains { !$0.completedDays.isEmpty } }
        ),
        Achievement(
            id: "perfect-day",
            title: "FLAWLESS",
            detail: "Finish everything in one day",
            symbol: "star.fill",
            color: Comic.yellow,
            isUnlocked: { habits in
                let todays = habits.filter { $0.isScheduled(on: Date()) }
                return !todays.isEmpty && todays.allSatisfy { $0.isCompleted(on: Date()) }
            }
        ),
        Achievement(
            id: "streak-7",
            title: "THE UNBROKEN",
            detail: "Reach a 7-day streak",
            symbol: "flame.fill",
            color: Comic.orange,
            isUnlocked: { $0.contains { $0.longestStreak >= 7 } }
        ),
        Achievement(
            id: "streak-30",
            title: "IRON WILL",
            detail: "Reach a 30-day streak",
            symbol: "shield.lefthalf.filled",
            color: Comic.red,
            isUnlocked: { $0.contains { $0.longestStreak >= 30 } }
        ),
        Achievement(
            id: "streak-100",
            title: "IMMORTAL",
            detail: "Reach a 100-day streak",
            symbol: "crown.fill",
            color: Color(red: 0.85, green: 0.65, blue: 0.0),
            isUnlocked: { $0.contains { $0.longestStreak >= 100 } }
        ),
        Achievement(
            id: "squad",
            title: "ASSEMBLE",
            detail: "Track 5 habits at once",
            symbol: "person.3.fill",
            color: Comic.blue,
            isUnlocked: { $0.count >= 5 }
        ),
        Achievement(
            id: "total-50",
            title: "GRINDER",
            detail: "50 total completions",
            symbol: "bolt.fill",
            color: Comic.orange,
            isUnlocked: { Gamification.totalCompletions($0) >= 50 }
        ),
        Achievement(
            id: "total-250",
            title: "POWERHOUSE",
            detail: "250 total completions",
            symbol: "bolt.horizontal.fill",
            color: Comic.red,
            isUnlocked: { Gamification.totalCompletions($0) >= 250 }
        ),
        Achievement(
            id: "total-1000",
            title: "COSMIC ENTITY",
            detail: "1,000 total completions",
            symbol: "globe.americas.fill",
            color: Color(red: 0.0, green: 0.65, blue: 0.55),
            isUnlocked: { Gamification.totalCompletions($0) >= 1_000 }
        )
    ]
}

// MARK: - Scoring

enum Gamification {

    /// XP for a single habit completion.
    static let xpPerCompletion = 10

    /// Streak lengths that pay a one-time bonus, and what they pay.
    static let milestones: [(days: Int, bonus: Int)] = [
        (7, 50), (14, 100), (30, 250), (60, 500), (100, 1_000), (365, 5_000)
    ]

    static func totalCompletions(_ habits: [Habit]) -> Int {
        habits.reduce(0) { $0 + $1.completedDays.count }
    }

    /// Total XP, derived from the habit data so it can never drift out of sync.
    static func totalXP(_ habits: [Habit]) -> Int {
        var xp = totalCompletions(habits) * xpPerCompletion
        for habit in habits {
            let best = habit.longestStreak
            for milestone in milestones where best >= milestone.days {
                xp += milestone.bonus
            }
        }
        return xp
    }

    /// Progress from the current rank to the next, 0...1.
    static func rankProgress(xp: Int) -> Double {
        let rank = HeroRank.rank(for: xp)
        guard let next = HeroRank.next(after: rank) else { return 1 }
        let span = Double(next.threshold - rank.threshold)
        guard span > 0 else { return 1 }
        return min(1, max(0, Double(xp - rank.threshold) / span))
    }

    static func unlockedAchievements(_ habits: [Habit]) -> Set<String> {
        Set(Achievement.all.filter { $0.isUnlocked(habits) }.map(\.id))
    }

    /// The milestone this completion just reached, if any — used for the big burst.
    static func milestoneReached(streak: Int) -> (days: Int, bonus: Int)? {
        milestones.first { $0.days == streak }
    }
}
