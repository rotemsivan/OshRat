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
            migrateLegacyLevelUp(on: existing)
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
        evaluateAchievements(in: context, now: now)
    }

    /// An account balance was corrected by hand. Counts as activity for the
    /// streak: keeping the balances true is exactly the habit worth rewarding
    /// in an app with no bank connection.
    static func recordBalanceUpdate(in context: ModelContext, now: Date = .now) {
        let progress = progress(in: context)
        award(XPRules.balanceUpdatedXP, reason: .balanceUpdated, to: progress, now: now)
        recordActivity(on: progress, now: now)
        try? context.save()
        evaluateAchievements(in: context, now: now)
    }

    /// The setup wizard finished. Pays the one-time milestones in one go so a
    /// brand-new user lands on the dashboard already past level 2 — the
    /// "front-load early wins" line in the plan.
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
        evaluateAchievements(in: context, now: now)
    }

    /// A budget line was deleted. A deleted row can't carry
    /// `BudgetItem.lastEditedAt`, so the budget achievements read this
    /// instead — removing a line changes a month's plan as much as editing
    /// one. The caller saves.
    static func recordBudgetLineDeleted(in context: ModelContext, now: Date = .now) {
        progress(in: context).budgetLastTouchedAt = now
    }

    // MARK: - Celebrations

    /// More than this many achievements unlocked in one pass are announced as
    /// a single "N new achievements" toast, followed only by the level the
    /// pass ended on. The first launch after achievements shipped can unlock
    /// ten at once; a toast each would be most of a minute of interruptions.
    static let celebrationBatchThreshold = 3

    /// The dashboard has shown the head of the queue; pop it (and any
    /// unreadable entries in front of it) so the next one can play.
    static func dismissCelebration(in context: ModelContext) {
        let progress = progress(in: context)
        guard let index = progress.pendingCelebrations.firstIndex(where: { Celebration(rawValue: $0) != nil })
        else {
            guard !progress.pendingCelebrations.isEmpty else { return }
            progress.pendingCelebrations.removeAll()
            try? context.save()
            return
        }
        progress.pendingCelebrations.removeSubrange(...index)
        try? context.save()
    }

    private static func enqueue(_ celebration: Celebration, on progress: UserProgress) {
        progress.pendingCelebrations.append(celebration.rawValue)
    }

    /// A level-up pending in the pre-queue `pendingLevelUpLevel` field goes to
    /// the front of the queue, once. The caller's next save persists it.
    private static func migrateLegacyLevelUp(on progress: UserProgress) {
        guard let level = progress.pendingLevelUpLevel else { return }
        progress.pendingCelebrations.insert(Celebration.levelUp(level).rawValue, at: 0)
        progress.pendingLevelUpLevel = nil
    }

    // MARK: - Achievements

    /// Check the whole store against the achievements catalogue, unlock
    /// anything newly satisfied and pay its XP — plus `budgetMonthMet` for
    /// each closed month that stayed under a pre-committed budget.
    ///
    /// Called from every entry point above and once when the dashboard
    /// appears, which is what catches month-boundary achievements and
    /// anything earned outside those paths (a deposit payout). A read of the
    /// ledger plus a rare write, so the cost is fine on a hand-entered store.
    ///
    /// Retroactive by design (ACHIEVEMENTS.md §5, option a): it reads facts,
    /// not the XP ledger, so on the first run a long-standing user unlocks
    /// what they've already done — patches *and* XP, with the level-up toasts
    /// queued rather than collapsed.
    static func evaluateAchievements(in context: ModelContext, now: Date = .now) {
        let progress = progress(in: context)
        let calendar = Calendar.current

        // First evaluation ever: budget achievements start counting from here.
        let epoch = progress.achievementsEpoch ?? now
        var changed = progress.achievementsEpoch == nil
        progress.achievementsEpoch = epoch

        let snapshot = makeSnapshot(progress: progress, epoch: epoch, now: now, calendar: calendar, in: context)

        // Budget months first, so a month that also unlocks `under-budget-1`
        // leaves the rarer achievement as the "last earned" marker.
        for month in AchievementEvaluator.budgetMonthsMet(snapshot) {
            let key = XPRules.budgetMonthKey(year: month.year, month: month.month)
            guard !progress.hasAwarded(key: key) else { continue }
            awardOnce(key: key, amount: XPRules.budgetMonthMetXP, reason: .budgetMonthMet, to: progress, now: now)
            changed = true
        }

        let satisfied = AchievementEvaluator.satisfied(snapshot)
        // Catalogue order, so a retroactive batch unlocks in shelf order.
        let newlyUnlocked = Achievement.catalogue.filter {
            $0.isReachable
                && satisfied.contains($0.id)
                && !progress.unlockedAchievements.contains($0.id)
        }
        // A big pass is announced once, as a batch, then the level it ended
        // on — see `celebrationBatchThreshold`. A small one announces each
        // patch followed by any level-up it caused, in order.
        let isBatch = newlyUnlocked.count > celebrationBatchThreshold
        let levelBeforeUnlocks = progress.level
        for achievement in newlyUnlocked {
            // The array membership *is* the idempotency guard — append first
            // so nothing can pay twice.
            progress.unlockedAchievements.append(achievement.id)
            if !isBatch {
                enqueue(.achievement(id: achievement.id), on: progress)
            }
            if achievement.xpReward > 0 {
                award(
                    achievement.xpReward,
                    reason: .achievementUnlocked,
                    to: progress,
                    now: now,
                    announcesLevelUp: !isBatch
                )
            }
            changed = true
        }
        if isBatch {
            enqueue(.achievementBatch(count: newlyUnlocked.count), on: progress)
            if progress.level > levelBeforeUnlocks {
                enqueue(.levelUp(progress.level), on: progress)
            }
        }

        if changed {
            try? context.save()
        }
    }

    /// Reduce the store to the plain values `AchievementEvaluator` reads.
    private static func makeSnapshot(
        progress: UserProgress,
        epoch: Date,
        now: Date,
        calendar: Calendar,
        in context: ModelContext
    ) -> AchievementSnapshot {
        let transactions = (try? context.fetch(
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.deletedAt == nil })
        )) ?? []
        let accounts = (try? context.fetch(
            FetchDescriptor<Account>(predicate: #Predicate { $0.deletedAt == nil })
        )) ?? []
        // Fetched directly rather than walked per transaction, so the ledger
        // scan doesn't fault in every row's attachments relationship. The
        // blobs are external storage and never loaded here.
        let attachments = (try? context.fetch(FetchDescriptor<TransactionAttachment>())) ?? []
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        let budgetItems = (try? context.fetch(FetchDescriptor<BudgetItem>())) ?? []

        var snapshot = AchievementSnapshot(achievementsEpoch: epoch, now: now, calendar: calendar)
        snapshot.longestStreak = progress.longestStreak

        snapshot.transactions = transactions.map { tx in
            TransactionFact(
                date: tx.date,
                createdAt: tx.createdAt,
                isTransfer: tx.isTransfer,
                isManualBalanceEdit: tx.isManualBalanceEdit,
                hasCategory: tx.category != nil,
                accountID: tx.account.map { AnyHashable($0.persistentModelID) },
                destinationAccountID: tx.destinationAccount.map { AnyHashable($0.persistentModelID) }
            )
        }

        snapshot.attachments = attachments.compactMap { attachment in
            guard let owner = attachment.transaction, owner.deletedAt == nil else { return nil }
            return AttachmentFact(transactionID: owner.persistentModelID, createdAt: attachment.createdAt)
        }

        snapshot.accounts = accounts.map {
            AccountFact(id: $0.persistentModelID, currencyCode: $0.currencyCode)
        }

        snapshot.deposits = accounts.filter(\.isDeposit).map { deposit in
            DepositFact(
                hasRate: deposit.interestRatePercent != nil,
                hasMaturityDate: deposit.maturityDate != nil,
                balance: deposit.balance,
                isPaidOut: deposit.payoutCompletedAt != nil,
                isReplenishable: deposit.isReplenishable,
                trancheEntryDates: deposit.liveDepositTranches.map(\.createdAt)
            )
        }

        snapshot.goals = goals.map {
            GoalFact(targetAmount: $0.targetAmount, createdAt: $0.createdAt, completedAt: $0.completedAt)
        }

        snapshot.budgetLastChangedAt = (budgetItems.compactMap(\.lastEditedAt) + [progress.budgetLastTouchedAt].compactMap { $0 })
            .max()

        snapshot.months = monthFacts(
            transactions: transactions,
            budgetItems: budgetItems,
            now: now,
            calendar: calendar,
            in: context
        )
        return snapshot
    }

    /// A money verdict for every closed month the ledger touches, each from
    /// `BudgetVsActual` — the same comparison the dashboard card shows, so an
    /// achievement can never disagree with what the user was looking at.
    ///
    /// Transactions are bucketed by month first so each comparison scans only
    /// its own month rather than the whole ledger (see the paged-`ScrollView`
    /// note in CLAUDE.md for what per-period full scans cost).
    private static func monthFacts(
        transactions: [Transaction],
        budgetItems: [BudgetItem],
        now: Date,
        calendar: Calendar,
        in context: ModelContext
    ) -> [MonthFact] {
        let currentMonth = YearMonth(now, calendar: calendar)
        let byMonth = Dictionary(grouping: transactions) { YearMonth($0.date, calendar: calendar) }
        guard let first = byMonth.keys.min() else { return [] }

        var profileDescriptor = FetchDescriptor<UserProfile>()
        profileDescriptor.fetchLimit = 1
        let preferredCurrency = (try? context.fetch(profileDescriptor).first?.preferredCurrencyCode) ?? "ILS"
        var fxDescriptor = FetchDescriptor<FXRateSnapshot>(sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)])
        fxDescriptor.fetchLimit = 1
        let fxSnapshot = try? context.fetch(fxDescriptor).first

        var facts: [MonthFact] = []
        var month = first
        // Closed months only — the current one can still change.
        while month < currentMonth {
            defer { month = month.next }
            guard let rows = byMonth[month], let anchor = month.start(in: calendar) else { continue }
            let report = BudgetVsActual(
                budgetItems: budgetItems,
                transactions: rows,
                preferredCurrency: preferredCurrency,
                fxSnapshot: fxSnapshot,
                scope: .month,
                calendar: calendar,
                now: anchor
            )
            // A month with a missing FX rate can't be judged either way.
            let complete = !report.fxUnavailable
            let spend = report.totalActualExpense
            facts.append(
                MonthFact(
                    month: month,
                    isUnderBudget: complete && report.totalPlannedExpense > 0 && !report.hasOverrun,
                    isSurplus: complete && report.actualNet > 0,
                    wantsShare: spend > 0
                        ? (report.wants.actual as NSDecimalNumber).doubleValue / (spend as NSDecimalNumber).doubleValue
                        : nil
                )
            )
        }
        return facts
    }

    // MARK: - Awarding

    /// Add XP, applying the daily cap when the reason is a farmable one, and
    /// raise the level-up flag if the total crossed a boundary.
    private static func award(
        _ amount: Int,
        reason: XPReason,
        to progress: UserProgress,
        now: Date,
        calendar: Calendar = .current,
        announcesLevelUp: Bool = true
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

        if levelAfter > levelBefore, announcesLevelUp {
            // Queued, not overwritten, so each level-up gets its own moment
            // (ACHIEVEMENTS.md §5, option a). One award that jumps two levels
            // still announces only where it landed. A batched achievement pass
            // turns this off and announces its final level itself.
            enqueue(.levelUp(levelAfter), on: progress)
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
