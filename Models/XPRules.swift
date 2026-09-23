import Foundation

/// Why a chunk of XP was handed out.
///
/// The reason travels with every award so the dashboard can always answer
/// "what did I just earn that for?" — one of GAMIFICATION.md's guardrails.
/// Raw values are persisted (as the last-award marker and inside the one-time
/// award ledger on `UserProgress`), so renaming a case would orphan history;
/// add cases, don't rename them.
enum XPReason: String, Codable, CaseIterable {
    /// A transaction — income, expense or transfer — was logged.
    case transactionLogged
    /// An account balance was corrected by hand, which keeps net worth honest.
    case balanceUpdated
    /// The setup wizard was finished.
    case profileCompleted
    case firstAccount
    case firstBudgetItem
    case firstTransaction
    /// A 7 / 30 / 100-day logging streak was reached.
    case streakMilestone
    /// Money was put toward a savings goal. Needs the Goals UI — not wired yet.
    case goalContribution
    /// A savings goal was reached. Needs the Goals UI — not wired yet.
    case goalCompleted
    /// A closed month finished under a budget that was settled before it began.
    case budgetMonthMet
    /// An achievement was unlocked. Pays the achievement's tier XP.
    case achievementUnlocked

    /// Shown on the dashboard's progress card. A plain `String` (not a
    /// `LocalizedStringKey`) to match `AccountType.hebrewLabel` — the app is
    /// Hebrew-only, so the literal *is* the final text.
    var hebrewLabel: String {
        switch self {
        case .transactionLogged: return "תנועה נרשמה"
        case .balanceUpdated:    return "יתרה עודכנה"
        case .profileCompleted:  return "השלמת ההגדרה"
        case .firstAccount:      return "החשבון הראשון"
        case .firstBudgetItem:   return "התקציב הראשון"
        case .firstTransaction:  return "התנועה הראשונה"
        case .streakMilestone:   return "רצף יומי"
        case .goalContribution:  return "הפקדה ליעד"
        case .goalCompleted:     return "יעד הושג"
        case .budgetMonthMet:    return "חודש בתוך התקציב"
        case .achievementUnlocked: return "הישג חדש"
        }
    }

    /// Whether awards for this reason count against the daily usage cap.
    ///
    /// Only the repeatable actions do. A one-time milestone or a streak bonus
    /// can't be ground out by definition, so capping those would just swallow
    /// a reward the user genuinely earned.
    var isDailyCapped: Bool {
        switch self {
        case .transactionLogged, .balanceUpdated, .goalContribution:
            return true
        case .profileCompleted, .firstAccount, .firstBudgetItem,
             .firstTransaction, .streakMilestone, .goalCompleted,
             .budgetMonthMet, .achievementUnlocked:
            return false
        }
    }
}

/// Every tunable number in the XP system, plus the pure maths that turns a
/// total into a level.
///
/// GAMIFICATION.md asks for exactly one place to balance the game from, so all
/// the amounts, caps and curve constants live here rather than being sprinkled
/// through `ProgressService`. Nothing in this file touches SwiftData or
/// SwiftUI, which is what lets the whole thing be unit-tested against fixed
/// dates and a fixed calendar.
enum XPRules {

    // MARK: - Earning

    /// Logging a transaction. Small on purpose: the point is a steady drip for
    /// keeping the ledger current, not a jackpot for typing fast.
    static let transactionLoggedXP = 5

    /// Correcting an account balance by hand. Slightly less than a
    /// transaction — it's a smaller act of bookkeeping, but it's the one that
    /// keeps net worth truthful, so it isn't free.
    static let balanceUpdatedXP = 3

    /// Any of the one-time setup milestones. Deliberately worth six logged
    /// transactions each: the plan wants early wins front-loaded, so finishing
    /// onboarding alone (90 XP) clears level 2 outright, so the wizard ends
    /// with a level-up toast on the first dashboard appearance.
    static let setupMilestoneXP = 30

    /// Putting money toward a goal. Farmable, so it shares the daily cap.
    /// Paid only once the Goals UI exists (ACHIEVEMENTS.md §8.6).
    static let goalContributionXP = 5

    /// Reaching a goal. One-time per goal, keyed by `goalCompletedKey`.
    static let goalCompletedXP = 100

    /// A closed month that stayed under a pre-committed budget. One-time per
    /// month, keyed by `budgetMonthKey`.
    static let budgetMonthMetXP = 60

    /// Ledger key for a budget month, so each month pays at most once.
    static func budgetMonthKey(year: Int, month: Int) -> String {
        "budget-\(year)-\(String(format: "%02d", month))"
    }

    /// Ledger key for a completed goal. `goalID` is a stable description of
    /// the goal's persistent identity.
    static func goalCompletedKey(goalID: String) -> String {
        "goal-\(goalID)"
    }

    /// The most XP the repeatable actions can produce in a single day.
    ///
    /// One shared cap rather than one per action: separate caps just move the
    /// farming around (log five rows, then nudge five balances). Set at six
    /// logged transactions' worth, which is far more than a real day of
    /// personal finance and still leaves the honest user never touching it.
    static let dailyUsageCap = 30

    /// Streak lengths that pay a bonus, and what each one pays. Rising steeply
    /// because the milestones are rare and getting to 100 days is the single
    /// hardest thing in the system.
    static let streakMilestones: [Int: Int] = [7: 50, 30: 150, 100: 500]

    /// The bonus for *arriving* at `streak` today, or `nil` on an ordinary day.
    static func streakBonus(forStreak streak: Int) -> Int? {
        streakMilestones[streak]
    }

    /// Ledger key for a streak bonus, so each milestone can only ever pay once
    /// — a user who hits 7 days, lapses, and climbs back to 7 doesn't get paid
    /// twice for the same rung.
    static func streakMilestoneKey(forStreak streak: Int) -> String {
        "streak-\(streak)"
    }

    // MARK: - Daily cap

    /// How much of `amount` may actually be paid, given what the capped
    /// sources have already produced today. Zero once the cap is spent.
    ///
    /// Note it clamps rather than refusing: a 5-point award with 3 points of
    /// headroom pays 3. Partial credit reads as "you've earned plenty today",
    /// where a flat refusal reads as a bug.
    static func cappedAward(_ amount: Int, alreadyEarnedToday: Int) -> Int {
        max(0, min(amount, dailyUsageCap - alreadyEarnedToday))
    }

    // MARK: - Streaks

    /// The streak after activity lands on `now`.
    ///
    /// Same day → unchanged (logging six things on Tuesday is one day of
    /// consistency, not six). Yesterday → one longer. Anything older, or no
    /// history at all → back to a streak of 1. Note that a lapse resets the
    /// *streak* and never the XP: GAMIFICATION.md is explicit that the system
    /// never punishes, and taking points away for a missed day would be
    /// exactly that.
    static func nextStreak(
        current: Int,
        lastActivity: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        guard let lastActivity else { return 1 }

        let today = calendar.startOfDay(for: now)
        let previous = calendar.startOfDay(for: lastActivity)

        // A clock that has gone backwards (timezone travel, a corrected
        // device clock) shouldn't silently break the streak, so "the future"
        // is treated as "already counted today".
        guard previous < today else { return max(current, 1) }

        let gap = calendar.dateComponents([.day], from: previous, to: today).day ?? 0
        return gap == 1 ? current + 1 : 1
    }

    // MARK: - Levels

    /// XP to get from level 1 to level 2. Every later level adds
    /// `levelCostStep` on top, so the curve rises gently and predictably
    /// instead of exploding the way a doubling curve would — until it hits
    /// `levelCostCeiling`, where it goes flat.
    ///
    /// The plateau is the point (ACHIEVEMENTS.md §1): a straight ramp put
    /// level 99 about 23 years of daily logging away, so nearly every user
    /// lived in levels 2–6. With the ceiling, levels 1–14 ramp and every
    /// level from 15 on costs the same, so progress keeps moving.
    static let baseLevelCost = 80
    static let levelCostStep = 30
    static let levelCostCeiling = 500

    /// Where the curve stops. Mostly a safety rail — it bounds the loop in
    /// `level(forTotalXP:)` — but it also gives the card something honest to
    /// say to a user who has genuinely run out of levels.
    static let maxLevel = 99

    /// XP needed to climb from `level` to the next one. Zero at the ceiling.
    static func xpToAdvance(from level: Int) -> Int {
        guard level >= 1, level < maxLevel else { return 0 }
        return min(baseLevelCost + levelCostStep * (level - 1), levelCostCeiling)
    }

    /// How many levels sit on the rising part of the curve before the
    /// ceiling takes over (14 with today's constants). Derived rather than
    /// hard-coded so retuning any one constant stays a one-line change.
    static var rampLength: Int {
        // Ceiling division: the first level whose arithmetic cost would
        // reach the ceiling is where the flat part begins.
        max(0, (levelCostCeiling - baseLevelCost + levelCostStep - 1) / levelCostStep)
    }

    /// Cumulative XP required to *reach* `level`. Level 1 costs nothing —
    /// everyone starts there.
    static func totalXP(toReach level: Int) -> Int {
        guard level > 1 else { return 0 }
        let steps = min(level, maxLevel) - 1
        let rampSteps = min(steps, rampLength)
        let flatSteps = max(0, steps - rampLength)
        // The ramp is an arithmetic series (`rampSteps` terms starting at
        // baseLevelCost, rising by levelCostStep); the plateau is flat.
        return rampSteps * baseLevelCost
            + levelCostStep * rampSteps * (rampSteps - 1) / 2
            + flatSteps * levelCostCeiling
    }

    /// The level a given lifetime total lands in.
    static func level(forTotalXP totalXP: Int) -> Int {
        guard totalXP > 0 else { return 1 }
        var level = 1
        var remaining = totalXP
        while level < maxLevel {
            let cost = xpToAdvance(from: level)
            guard remaining >= cost else { break }
            remaining -= cost
            level += 1
        }
        return level
    }

    /// Everything the progress card needs to draw itself.
    static func progress(forTotalXP totalXP: Int) -> LevelProgress {
        let clamped = max(0, totalXP)
        let level = level(forTotalXP: clamped)
        let cost = xpToAdvance(from: level)
        return LevelProgress(
            level: level,
            xpIntoLevel: clamped - self.totalXP(toReach: level),
            xpForNextLevel: cost
        )
    }
}

/// Where the user stands inside their current level — the shape the dashboard
/// card and the level-up toast both read from.
struct LevelProgress: Equatable {
    let level: Int
    /// XP earned since reaching `level`.
    let xpIntoLevel: Int
    /// XP the whole level costs. Zero at the ceiling, which is what
    /// `isMaxLevel` keys on.
    let xpForNextLevel: Int

    var isMaxLevel: Bool { xpForNextLevel == 0 }

    /// XP still to go. Zero at the ceiling.
    var xpRemaining: Int { max(0, xpForNextLevel - xpIntoLevel) }

    /// 0…1 for the progress bar. A finished curve reads as full rather than
    /// empty — dividing by a zero cost would otherwise show a maxed-out user
    /// a bar with nothing in it.
    var fraction: Double {
        guard xpForNextLevel > 0 else { return 1 }
        return min(max(Double(xpIntoLevel) / Double(xpForNextLevel), 0), 1)
    }
}
