import SwiftUI

// MARK: - Ranks

struct HeroRank: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let threshold: Int
    let color: Color

    static let all: [HeroRank] = [
        HeroRank(title: "Rookie",    threshold: 0,     color: Palette.ink.opacity(0.6)),
        HeroRank(title: "Sidekick",  threshold: 250,   color: Palette.blue),
        HeroRank(title: "Vigilante", threshold: 750,   color: Palette.orange),
        HeroRank(title: "Hero",      threshold: 1_500, color: Palette.red),
        HeroRank(title: "Avenger",   threshold: 3_000, color: Color(red: 0.55, green: 0.2, blue: 0.75)),
        HeroRank(title: "Legend",    threshold: 6_000, color: Color(red: 0.85, green: 0.65, blue: 0.0)),
        HeroRank(title: "Cosmic",    threshold: 12_000, color: Color(red: 0.0, green: 0.65, blue: 0.55))
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
            title: "Origin Story",
            detail: "Create your first habit",
            symbol: "sparkles",
            color: Palette.blue,
            isUnlocked: { !$0.isEmpty }
        ),
        Achievement(
            id: "first-done",
            title: "First Blood",
            detail: "Complete a habit once",
            symbol: "checkmark.seal.fill",
            color: Palette.red,
            isUnlocked: { $0.contains { !$0.completedDays.isEmpty } }
        ),
        Achievement(
            id: "perfect-day",
            title: "Flawless",
            detail: "Finish everything in one day",
            symbol: "star.fill",
            color: Palette.yellow,
            isUnlocked: { habits in
                let todays = habits.filter { $0.isScheduled(on: Date()) }
                return !todays.isEmpty && todays.allSatisfy { $0.isCompleted(on: Date()) }
            }
        ),
        Achievement(
            id: "streak-7",
            title: "The Unbroken",
            detail: "Reach a 7-day streak",
            symbol: "flame.fill",
            color: Palette.orange,
            isUnlocked: { $0.contains { $0.longestStreak >= 7 } }
        ),
        Achievement(
            id: "streak-30",
            title: "Iron Will",
            detail: "Reach a 30-day streak",
            symbol: "shield.lefthalf.filled",
            color: Palette.red,
            isUnlocked: { $0.contains { $0.longestStreak >= 30 } }
        ),
        Achievement(
            id: "streak-100",
            title: "Immortal",
            detail: "Reach a 100-day streak",
            symbol: "crown.fill",
            color: Color(red: 0.85, green: 0.65, blue: 0.0),
            isUnlocked: { $0.contains { $0.longestStreak >= 100 } }
        ),
        Achievement(
            id: "squad",
            title: "Assemble",
            detail: "Track 5 habits at once",
            symbol: "person.3.fill",
            color: Palette.blue,
            isUnlocked: { $0.count >= 5 }
        ),
        Achievement(
            id: "total-50",
            title: "Grinder",
            detail: "50 total completions",
            symbol: "bolt.fill",
            color: Palette.orange,
            isUnlocked: { Gamification.totalCompletions($0) >= 50 }
        ),
        Achievement(
            id: "total-250",
            title: "Powerhouse",
            detail: "250 total completions",
            symbol: "bolt.horizontal.fill",
            color: Palette.red,
            isUnlocked: { Gamification.totalCompletions($0) >= 250 }
        ),
        Achievement(
            id: "total-1000",
            title: "Cosmic Entity",
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
