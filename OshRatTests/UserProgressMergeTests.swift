import Testing
import Foundation
import SwiftData
@testable import OshRat

/// Two devices each made a progress row before sync met them; the kept one
/// absorbs the other without losing or double-paying anything.
@MainActor
struct UserProgressMergeTests {

    private static func day(_ n: Int) -> Date {
        Date(timeIntervalSince1970: 1_790_000_000 + Double(n) * 86_400)
    }

    @Test func nothingEarnedIsLost() {
        let kept = UserProgress()
        kept.totalXP = 1200
        kept.longestStreak = 9
        kept.currentStreak = 2
        kept.lastActivityDate = Self.day(10)
        kept.awardedKeys = ["onboardingDone", "streak-7"]
        kept.unlockedAchievements = ["log-100"]
        kept.achievementsEpoch = Self.day(5)

        let other = UserProgress()
        other.totalXP = 900
        other.longestStreak = 14
        other.currentStreak = 6
        other.lastActivityDate = Self.day(12)
        other.awardedKeys = ["streak-7", "firstBudgetItem"]
        other.unlockedAchievements = ["log-100", "under-budget-1"]
        other.achievementsEpoch = Self.day(3)
        other.budgetLastTouchedAt = Self.day(11)

        kept.absorb(other)

        #expect(kept.totalXP == 1200)
        #expect(kept.longestStreak == 14)
        // The current streak follows whichever device logged last.
        #expect(kept.currentStreak == 6)
        #expect(kept.lastActivityDate == Self.day(12))
        // Paid on either device stays paid — and only once.
        #expect(kept.awardedKeys == ["onboardingDone", "streak-7", "firstBudgetItem"])
        #expect(kept.unlockedAchievements == ["log-100", "under-budget-1"])
        #expect(kept.achievementsEpoch == Self.day(3))
        #expect(kept.budgetLastTouchedAt == Self.day(11))
    }

    /// An older streak on the other device doesn't overwrite today's.
    @Test func aStaleStreakDoesNotWin() {
        let kept = UserProgress()
        kept.currentStreak = 4
        kept.lastActivityDate = Self.day(20)
        let other = UserProgress()
        other.currentStreak = 30
        other.lastActivityDate = Self.day(2)

        kept.absorb(other)
        #expect(kept.currentStreak == 4)
        #expect(kept.lastActivityDate == Self.day(20))
    }
}
