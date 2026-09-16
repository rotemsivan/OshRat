import Foundation
import SwiftData

/// The XP engine — the one place that hands out points, moves the streak on,
/// and notices a level-up.
///
/// GAMIFICATION.md asks for this to be called from the app's *existing*
/// data-write points rather than scattered through the UI, so there are only a
/// handful of entry points here and each one maps to something the user
/// actually did: logged a transaction, corrected a balance, finished setup.
/// Each one is idempotent-safe to call, enforces the daily cap, and saves —
/// callers don't have to remember to, and a save that follows immediately
/// afterwards costs nothing.
///
/// All the judgement lives in `XPRules` (a pure, tested value type). This
/// layer only reads and writes the store.
enum ProgressService {

    // MARK: - The row

    /// The progress row, created on first use.
    ///
    /// Resolves to the *oldest* row if several exist. That can't happen today
    /// (one device, one row) but it's the behaviour we want the day CloudKit
    /// is switched on and two devices have each made one — the older row is
    /// the one with the longer history behind it.
    static func progress(in context: ModelContext) -> UserProgress {
        var descriptor = FetchDescriptor<UserProgress>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let created = UserProgress()
        context.insert(created)
        return created
    }

    // MARK: - Entry points

    /// A transaction was logged — the core loop of the app, and the main way
    /// XP accumulates. Also the moment the streak advances.
    ///
    /// Call this only for *new* rows. Editing an existing transaction is
    /// bookkeeping hygiene, not new activity, and paying for it would make
    /// "open a row and save it again" a way to farm points.
    static func recordTransactionLogged(in context: ModelContext, now: Date = .now) {
        let progress = progress(in: context)
        // Ordered smallest-first on purpose: each award overwrites the
        // "last earned" marker the dashboard reads, so the rare, notable one
        // (a first transaction, a streak milestone) is what the user is left
        // looking at rather than the routine +5 that came with it.
        award(XPRules.transactionLoggedXP, reason: .transactionLogged, to: progress, now: now)
        awardOnce(
            key: XPReason.firstTransaction.rawValue,
            amount: XPRules.setupMilestoneXP,
            reason: .firstTransaction,
            to: progress,
            now: now
        )
        recordActivity(on: progress, now: now)
        try? context.save()
    }

    /// An account balance was corrected by hand. Counts as activity for the
    /// streak: keeping the balances true is exactly the habit worth rewarding
    /// in an app with no bank connection.
    static func recordBalanceUpdate(in context: ModelContext, now: Date = .now) {
        let progress = progress(in: context)
        award(XPRules.balanceUpdatedXP, reason: .balanceUpdated, to: progress, now: now)
        recordActivity(on: progress, now: now)
        try? context.save()
    }

    /// The setup wizard finished. Pays the one-time milestones in one go so a
    /// brand-new user lands on the dashboard already most of the way to level
    /// 2 — the "front-load early wins" line in the plan.
    ///
    /// The account and budget milestones are conditional because both steps of
    /// the wizard can legitimately be left empty.
    static func recordOnboardingCompleted(
        hasAccount: Bool,
        hasBudgetItem: Bool,
        in context: ModelContext,
        now: Date = .now
    ) {
        let progress = progress(in: context)
        recordActivity(on: progress, now: now)
        // Setup milestones come after the streak here (the reverse of the
        // other entry points): day one can't be a streak milestone, so the
        // notable award to leave showing is "you finished setting up".
        awardOnce(
            key: XPReason.profileCompleted.rawValue,
            amount: XPRules.setupMilestoneXP,
            reason: .profileCompleted,
            to: progress,
            now: now
        )
        if hasAccount {
            awardOnce(
                key: XPReason.firstAccount.rawValue,
                amount: XPRules.setupMilestoneXP,
                reason: .firstAccount,
                to: progress,
                now: now
            )
        }
        if hasBudgetItem {
            awardOnce(
                key: XPReason.firstBudgetItem.rawValue,
                amount: XPRules.setupMilestoneXP,
                reason: .firstBudgetItem,
                to: progress,
                now: now
            )
        }
        try? context.save()
    }

    /// The dashboard has shown the level-up toast; put the flag down so it
    /// doesn't fire again on the next render.
    static func clearPendingLevelUp(in context: ModelContext) {
        let progress = progress(in: context)
        guard progress.pendingLevelUpLevel != nil else { return }
        progress.pendingLevelUpLevel = nil
        try? context.save()
    }

    // MARK: - Awarding

    /// Add XP, applying the daily cap when the reason is a farmable one, and
    /// raise the level-up flag if the total crossed a boundary.
    private static func award(
        _ amount: Int,
        reason: XPReason,
        to progress: UserProgress,
        now: Date,
        calendar: Calendar = .current
    ) {
        var payable = amount

        if reason.isDailyCapped {
            rollDailyCapWindow(on: progress, now: now, calendar: calendar)
            payable = XPRules.cappedAward(amount, alreadyEarnedToday: progress.dailyCappedXP)
            progress.dailyCappedXP += payable
        }

        // Nothing to pay — the cap is spent for today. Deliberately silent:
        // the user is told what they *earned*, never nagged about a ceiling
        // they hit by using the app enthusiastically.
        guard payable > 0 else { return }

        let levelBefore = progress.level
        progress.totalXP += payable
        let levelAfter = progress.level

        if levelAfter > levelBefore {
            // Latest wins if several level-ups stack before the toast shows —
            // the user wants to hear the level they're on now, not the one
            // they passed through.
            progress.pendingLevelUpLevel = levelAfter
        }

        progress.lastAwardReasonRaw = reason.rawValue
        progress.lastAwardXP = payable
    }

    /// Pay an award that can only ever land once, keyed in the ledger.
    private static func awardOnce(
        key: String,
        amount: Int,
        reason: XPReason,
        to progress: UserProgress,
        now: Date
    ) {
        guard !progress.hasAwarded(key: key) else { return }
        // Record the key before awarding: if the award pays nothing the
        // milestone is still spent, and a half-applied state can't pay twice.
        progress.awardedKeys.append(key)
        award(amount, reason: reason, to: progress, now: now)
    }

    /// Reset the daily counter when the stored window is from an earlier day.
    private static func rollDailyCapWindow(
        on progress: UserProgress,
        now: Date,
        calendar: Calendar
    ) {
        let today = calendar.startOfDay(for: now)
        let isSameDay = progress.dailyCapDate
            .map { calendar.startOfDay(for: $0) == today } ?? false
        guard !isSameDay else { return }

        progress.dailyCappedXP = 0
        progress.dailyCapDate = today
    }

    // MARK: - Streak

    /// Move the streak on for activity landing on `now`, and pay a milestone
    /// bonus if this is the day it was reached.
    private static func recordActivity(
        on progress: UserProgress,
        now: Date,
        calendar: Calendar = .current
    ) {
        let updated = XPRules.nextStreak(
            current: progress.currentStreak,
            lastActivity: progress.lastActivityDate,
            now: now,
            calendar: calendar
        )

        progress.currentStreak = updated
        progress.longestStreak = max(progress.longestStreak, updated)
        progress.lastActivityDate = now

        // Milestones pay once ever, not once per climb — see
        // `XPRules.streakMilestoneKey`.
        if let bonus = XPRules.streakBonus(forStreak: updated) {
            awardOnce(
                key: XPRules.streakMilestoneKey(forStreak: updated),
                amount: bonus,
                reason: .streakMilestone,
                to: progress,
                now: now
            )
        }
    }
}
