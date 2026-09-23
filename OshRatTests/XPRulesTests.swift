import Testing
import Foundation
@testable import OshRat

/// The XP system's maths. `XPRules` is a pure value type — no store, no
/// clock — so everything here runs against fixed dates and a fixed calendar.
///
/// These are the numbers the whole feature is balanced on, so the tests spell
/// the expected values out longhand rather than recomputing them from the
/// constants: a test that re-derives the answer from the same formula would
/// pass just as happily if the formula were wrong.
struct XPRulesTests {

    /// Gregorian calendar pinned to UTC so streak day-counts don't shift with
    /// the test machine's timezone.
    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - The level curve

    @Test func levelOneCostsNothing() {
        #expect(XPRules.level(forTotalXP: 0) == 1)
        #expect(XPRules.level(forTotalXP: 79) == 1)
        #expect(XPRules.totalXP(toReach: 1) == 0)
    }

    /// 80 / 190 / 330 / 500 — on the ramp, each level costs 30 more than
    /// the one before.
    @Test func levelBoundariesRiseByAFixedStep() {
        #expect(XPRules.totalXP(toReach: 2) == 80)
        #expect(XPRules.totalXP(toReach: 3) == 190)
        #expect(XPRules.totalXP(toReach: 4) == 330)
        #expect(XPRules.totalXP(toReach: 5) == 500)
        #expect(XPRules.totalXP(toReach: 10) == 1_800)
    }

    @Test func levelIsTheHighestBoundaryReached() {
        #expect(XPRules.level(forTotalXP: 80) == 2)
        #expect(XPRules.level(forTotalXP: 189) == 2)
        #expect(XPRules.level(forTotalXP: 190) == 3)
        #expect(XPRules.level(forTotalXP: 329) == 3)
        #expect(XPRules.level(forTotalXP: 330) == 4)
    }

    /// Onboarding pays three 30-XP milestones; the wizard should end with a
    /// level-up rather than just short of one.
    @Test func onboardingClearsLevelTwo() {
        #expect(XPRules.level(forTotalXP: 3 * XPRules.setupMilestoneXP) == 2)
    }

    // MARK: - The plateau

    /// Levels 1–14 ramp; 15 onwards all cost the ceiling.
    @Test func theRampMeetsThePlateauAtLevelFifteen() {
        #expect(XPRules.rampLength == 14)
        #expect(XPRules.xpToAdvance(from: 13) == 440)
        #expect(XPRules.xpToAdvance(from: 14) == 470)
        #expect(XPRules.xpToAdvance(from: 15) == 500)
        #expect(XPRules.xpToAdvance(from: 16) == 500)
        #expect(XPRules.xpToAdvance(from: 60) == 500)
        #expect(XPRules.xpToAdvance(from: XPRules.maxLevel) == 0)
    }

    @Test func plateauTotalsMatchThePacingTable() {
        #expect(XPRules.totalXP(toReach: 15) == 3_850)
        #expect(XPRules.totalXP(toReach: 20) == 6_350)
        #expect(XPRules.totalXP(toReach: 50) == 21_350)
        #expect(XPRules.totalXP(toReach: 99) == 45_850)
    }

    /// The piecewise closed form has to agree with simply adding up every
    /// level's cost — cheap, and it catches any slip in the algebra.
    @Test func closedFormAgreesWithANaiveSum() {
        var running = 0
        for level in 1...XPRules.maxLevel {
            #expect(XPRules.totalXP(toReach: level) == running)
            running += XPRules.xpToAdvance(from: level)
        }
    }

    /// `level(forTotalXP:)` and `totalXP(toReach:)` have to be exact inverses,
    /// or the progress bar would sit at a fraction the level doesn't match.
    @Test func levelAndTotalAgreeAtEveryBoundary() {
        for level in 1...XPRules.maxLevel {
            let boundary = XPRules.totalXP(toReach: level)
            #expect(XPRules.level(forTotalXP: boundary) == level)
            if level > 1 {
                #expect(XPRules.level(forTotalXP: boundary - 1) == level - 1)
            }
        }
    }

    @Test func negativeTotalsClampToTheStart() {
        let progress = XPRules.progress(forTotalXP: -50)
        #expect(progress.level == 1)
        #expect(progress.xpIntoLevel == 0)
        #expect(progress.fraction == 0)
    }

    // MARK: - Progress within a level

    @Test func progressReportsPositionInsideTheCurrentLevel() {
        // 120 XP: level 2 (which starts at 80), 40 into a level costing 110.
        let progress = XPRules.progress(forTotalXP: 120)
        #expect(progress.level == 2)
        #expect(progress.xpIntoLevel == 40)
        #expect(progress.xpForNextLevel == 110)
        #expect(progress.xpRemaining == 70)
        #expect(progress.isMaxLevel == false)
        #expect(abs(progress.fraction - (40.0 / 110.0)) < 0.0001)
    }

    @Test func freshlyLevelledUpStartsAnEmptyBar() {
        let progress = XPRules.progress(forTotalXP: 190)
        #expect(progress.level == 3)
        #expect(progress.xpIntoLevel == 0)
        #expect(progress.fraction == 0)
    }

    /// At the ceiling there's no next level to be a fraction of. The bar has
    /// to read full rather than empty — dividing by a zero cost would show a
    /// maxed-out user nothing at all.
    @Test func theCeilingReadsAsCompleteNotEmpty() {
        let enormous = XPRules.totalXP(toReach: XPRules.maxLevel) + 1_000_000
        let progress = XPRules.progress(forTotalXP: enormous)
        #expect(progress.level == XPRules.maxLevel)
        #expect(progress.isMaxLevel)
        #expect(progress.fraction == 1)
        #expect(progress.xpRemaining == 0)
    }

    // MARK: - The daily cap

    @Test func awardsPassThroughBelowTheCap() {
        #expect(XPRules.cappedAward(5, alreadyEarnedToday: 0) == 5)
        #expect(XPRules.cappedAward(5, alreadyEarnedToday: 10) == 5)
    }

    /// Partial credit at the boundary: with 3 points of headroom a 5-point
    /// award pays 3, not 0 and not 5.
    @Test func awardsClampToTheRemainingHeadroom() {
        let almostSpent = XPRules.dailyUsageCap - 3
        #expect(XPRules.cappedAward(5, alreadyEarnedToday: almostSpent) == 3)
    }

    @Test func aSpentCapPaysNothingAndNeverGoesNegative() {
        #expect(XPRules.cappedAward(5, alreadyEarnedToday: XPRules.dailyUsageCap) == 0)
        #expect(XPRules.cappedAward(5, alreadyEarnedToday: XPRules.dailyUsageCap + 99) == 0)
    }

    @Test func onlyRepeatableActionsAreCapped() {
        #expect(XPReason.transactionLogged.isDailyCapped)
        #expect(XPReason.balanceUpdated.isDailyCapped)
        #expect(XPReason.goalContribution.isDailyCapped)
        // One-time and streak awards can't be farmed by definition, so capping
        // them would only swallow a reward that was genuinely earned.
        #expect(XPReason.firstAccount.isDailyCapped == false)
        #expect(XPReason.streakMilestone.isDailyCapped == false)
        #expect(XPReason.goalCompleted.isDailyCapped == false)
        #expect(XPReason.budgetMonthMet.isDailyCapped == false)
        #expect(XPReason.achievementUnlocked.isDailyCapped == false)
    }

    @Test func budgetMonthKeysArePaddedAndDistinct() {
        #expect(XPRules.budgetMonthKey(year: 2026, month: 9) == "budget-2026-09")
        #expect(XPRules.budgetMonthKey(year: 2026, month: 10) == "budget-2026-10")
    }

    // MARK: - Streaks

    @Test func firstEverActivityStartsAtOne() {
        let streak = XPRules.nextStreak(
            current: 0,
            lastActivity: nil,
            now: Self.date(2026, 9, 13),
            calendar: Self.calendar
        )
        #expect(streak == 1)
    }

    /// Logging six things on one Tuesday is one day of consistency, not six.
    @Test func sameDayActivityDoesNotAdvanceTheStreak() {
        let streak = XPRules.nextStreak(
            current: 4,
            lastActivity: Self.date(2026, 9, 13),
            now: Self.date(2026, 9, 13),
            calendar: Self.calendar
        )
        #expect(streak == 4)
    }

    @Test func yesterdayExtendsTheStreak() {
        let streak = XPRules.nextStreak(
            current: 4,
            lastActivity: Self.date(2026, 9, 12),
            now: Self.date(2026, 9, 13),
            calendar: Self.calendar
        )
        #expect(streak == 5)
    }

    @Test func aMissedDayStartsOver() {
        let streak = XPRules.nextStreak(
            current: 30,
            lastActivity: Self.date(2026, 9, 11),
            now: Self.date(2026, 9, 13),
            calendar: Self.calendar
        )
        #expect(streak == 1)
    }

    /// A device clock that has gone backwards (timezone travel, a manual
    /// correction) mustn't silently break a streak the user has earned.
    @Test func aFutureLastActivityLeavesTheStreakAlone() {
        let streak = XPRules.nextStreak(
            current: 12,
            lastActivity: Self.date(2026, 9, 20),
            now: Self.date(2026, 9, 13),
            calendar: Self.calendar
        )
        #expect(streak == 12)
    }

    /// Late-evening to early-morning is still one calendar day apart — the
    /// comparison has to normalise to day boundaries, not elapsed hours.
    @Test func streakCountsCalendarDaysNotElapsedHours() {
        let lateMonday = Self.calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 14, hour: 23, minute: 50)
        )!
        let earlyTuesday = Self.calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 15, hour: 0, minute: 10)
        )!
        let streak = XPRules.nextStreak(
            current: 2,
            lastActivity: lateMonday,
            now: earlyTuesday,
            calendar: Self.calendar
        )
        #expect(streak == 3)
    }

    // MARK: - Streak milestones

    @Test func onlyTheMilestoneDaysPayABonus() {
        #expect(XPRules.streakBonus(forStreak: 7) == 50)
        #expect(XPRules.streakBonus(forStreak: 30) == 150)
        #expect(XPRules.streakBonus(forStreak: 100) == 500)
        #expect(XPRules.streakBonus(forStreak: 6) == nil)
        #expect(XPRules.streakBonus(forStreak: 8) == nil)
        #expect(XPRules.streakBonus(forStreak: 0) == nil)
    }

    /// The key is what stops a milestone paying twice, so its shape matters as
    /// much as the bonus does.
    @Test func milestoneKeysAreDistinctPerRung() {
        #expect(XPRules.streakMilestoneKey(forStreak: 7) == "streak-7")
        #expect(XPRules.streakMilestoneKey(forStreak: 30) != XPRules.streakMilestoneKey(forStreak: 7))
    }

    // MARK: - Reasons

    /// Raw values are persisted on `UserProgress`, so a rename would orphan
    /// history. Pin them.
    @Test func reasonRawValuesAreStable() {
        #expect(XPReason.transactionLogged.rawValue == "transactionLogged")
        #expect(XPReason.balanceUpdated.rawValue == "balanceUpdated")
        #expect(XPReason.profileCompleted.rawValue == "profileCompleted")
        #expect(XPReason.firstAccount.rawValue == "firstAccount")
        #expect(XPReason.firstBudgetItem.rawValue == "firstBudgetItem")
        #expect(XPReason.firstTransaction.rawValue == "firstTransaction")
        #expect(XPReason.streakMilestone.rawValue == "streakMilestone")
        #expect(XPReason.goalContribution.rawValue == "goalContribution")
        #expect(XPReason.goalCompleted.rawValue == "goalCompleted")
        #expect(XPReason.budgetMonthMet.rawValue == "budgetMonthMet")
        #expect(XPReason.achievementUnlocked.rawValue == "achievementUnlocked")
    }

    @Test func everyReasonHasALabelToShowTheUser() {
        for reason in XPReason.allCases {
            #expect(reason.hebrewLabel.isEmpty == false)
        }
    }
}
