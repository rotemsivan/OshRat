import Testing
import Foundation
@testable import OshRat

/// The achievements rules. `AchievementEvaluator` is pure — plain-value
/// snapshot in, ids out — so every guard runs against fixed dates and a
/// fixed calendar.
///
/// The emphasis (ACHIEVEMENTS.md §9) is on the anti-farming guards *failing*
/// when only the naive condition is met: those are the rules that are easy
/// to break without noticing, because the honest path still passes.
struct AchievementEvaluatorTests {

    // MARK: - Fixtures

    /// Gregorian, pinned to UTC so day and month boundaries don't move with
    /// the test machine's timezone.
    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// Epoch at the start of 2026, "today" late in September.
    private static func snapshot() -> AchievementSnapshot {
        AchievementSnapshot(
            achievementsEpoch: date(2026, 1, 1, hour: 0),
            now: date(2026, 9, 23),
            calendar: calendar
        )
    }

    private static func row(
        date: Date,
        createdAt: Date?,
        isTransfer: Bool = false,
        isManualBalanceEdit: Bool = false,
        hasCategory: Bool = false,
        account: String? = "main",
        destination: String? = nil
    ) -> TransactionFact {
        TransactionFact(
            date: date,
            createdAt: createdAt,
            isTransfer: isTransfer,
            isManualBalanceEdit: isManualBalanceEdit,
            hasCategory: hasCategory,
            accountID: account.map(AnyHashable.init),
            destinationAccountID: destination.map(AnyHashable.init)
        )
    }

    /// `count` real rows dated inside `month`, entered on `entryDays`
    /// distinct days (round-robin across the month's first days).
    private static func rows(in month: YearMonth, count: Int, entryDays: Int) -> [TransactionFact] {
        (0..<count).map { index in
            let day = index % max(entryDays, 1) + 1
            let when = date(month.year, month.month, day)
            return row(date: when, createdAt: when)
        }
    }

    private static func satisfied(_ snapshot: AchievementSnapshot) -> Set<String> {
        AchievementEvaluator.satisfied(snapshot)
    }

    // MARK: - The catalogue

    @Test func catalogueHasTwentyFourUniqueIDs() {
        let ids = Achievement.catalogue.map(\.id)
        #expect(ids.count == 24)
        #expect(Set(ids).count == 24)
    }

    /// 11 bronze + 7 silver + 3 gold that pay, streaks at zero.
    @Test func catalogueTotalsThreeThousandFourHundredXP() {
        #expect(Achievement.catalogue.map(\.xpReward).reduce(0, +) == 3_400)
    }

    /// `XPRules.streakMilestones` already pays for these events.
    @Test func streakPatchesPayNothing() {
        for id in ["streak-7", "streak-30", "streak-100"] {
            #expect(Achievement.withID(id)?.xpReward == 0)
        }
    }

    /// Goals has no UI yet, so these stay visible but locked.
    @Test func goalPatchesAreNotYetReachable() {
        #expect(Achievement.withID("first-goal")?.isReachable == false)
        #expect(Achievement.withID("goal-done")?.isReachable == false)
        #expect(Achievement.catalogue.filter { !$0.isReachable }.count == 2)
    }

    /// Every id the evaluator can grant has to exist in the catalogue, or
    /// `ProgressService` would silently never unlock it.
    @Test func everyGrantableIDIsCatalogued() {
        var s = Self.snapshot()
        s.longestStreak = 100
        let everything = Self.satisfied(s)
        for id in everything {
            #expect(Achievement.withID(id) != nil)
        }
    }

    // MARK: - Streaks

    @Test func streakPatchesFollowTheLongestStreak() {
        var s = Self.snapshot()
        s.longestStreak = 29
        let ids = Self.satisfied(s)
        #expect(ids.contains("streak-7"))
        #expect(!ids.contains("streak-30"))
    }

    // MARK: - Logging volume

    /// The naive condition (1,000 rows) met in a single afternoon.
    @Test func aThousandRowsOnOneEntryDayIsNotAHistory() {
        var s = Self.snapshot()
        let sameDay = Self.date(2026, 5, 1)
        s.transactions = (0..<1_000).map { _ in Self.row(date: sameDay, createdAt: sameDay) }
        #expect(!Self.satisfied(s).contains("log-1000"))
        #expect(!Self.satisfied(s).contains("log-100"))
    }

    @Test func aThousandRowsOverHalfAYearIs() {
        var s = Self.snapshot()
        let start = Self.date(2026, 1, 1)
        s.transactions = (0..<1_000).map { index in
            let when = Self.calendar.date(byAdding: .day, value: index % 180, to: start)!
            return Self.row(date: when, createdAt: when)
        }
        let ids = Self.satisfied(s)
        #expect(ids.contains("log-1000"))
        #expect(ids.contains("log-500"))
        #expect(ids.contains("log-100"))
    }

    /// Legacy rows (`createdAt == nil`) count toward the total but add no
    /// entry day: 70 legacy + 30 rows on 30 distinct days still makes it.
    @Test func legacyRowsCountTowardTotalsButNotSpread() {
        var s = Self.snapshot()
        let legacy = (0..<70).map { _ in Self.row(date: Self.date(2025, 3, 1), createdAt: nil) }
        let spread = (0..<30).map { index in
            let when = Self.calendar.date(byAdding: .day, value: index, to: Self.date(2026, 2, 1))!
            return Self.row(date: when, createdAt: when)
        }
        s.transactions = legacy + spread
        #expect(Self.satisfied(s).contains("log-100"))

        // …but all-legacy contributes no days at all.
        s.transactions = (0..<100).map { _ in Self.row(date: Self.date(2025, 3, 1), createdAt: nil) }
        #expect(!Self.satisfied(s).contains("log-100"))
    }

    /// Transfers and balance markers aren't logging.
    @Test func bookkeepingRowsDoNotCountAsLogging() {
        var s = Self.snapshot()
        let start = Self.date(2026, 1, 1)
        s.transactions = (0..<100).map { index in
            let when = Self.calendar.date(byAdding: .day, value: index, to: start)!
            return Self.row(date: when, createdAt: when, isTransfer: true, destination: "savings")
        }
        #expect(!Self.satisfied(s).contains("log-100"))
    }

    // MARK: - Attachments

    /// 25 files on one receipt is still one receipt.
    @Test func manyAttachmentsOnOneTransactionIsNotAFilingHabit() {
        var s = Self.snapshot()
        s.attachments = (0..<25).map { index in
            AttachmentFact(
                transactionID: AnyHashable("tx-1"),
                createdAt: Self.calendar.date(byAdding: .day, value: index, to: Self.date(2026, 3, 1))!
            )
        }
        let ids = Self.satisfied(s)
        #expect(ids.contains("first-attachment"))
        #expect(!ids.contains("attachments-25"))
    }

    @Test func attachmentsOnDistinctTransactionsAcrossDaysCount() {
        var s = Self.snapshot()
        s.attachments = (0..<25).map { index in
            AttachmentFact(
                transactionID: AnyHashable("tx-\(index)"),
                createdAt: Self.calendar.date(byAdding: .day, value: index % 10, to: Self.date(2026, 3, 1))!
            )
        }
        #expect(Self.satisfied(s).contains("attachments-25"))

        // Same 25 transactions, all filed on one day.
        s.attachments = (0..<25).map { AttachmentFact(transactionID: AnyHashable("tx-\($0)"), createdAt: Self.date(2026, 3, 1)) }
        #expect(!Self.satisfied(s).contains("attachments-25"))
    }

    // MARK: - Balance checks

    /// Nudging one balance ten times in a day counts once.
    @Test func balanceChecksCountOncePerAccountPerDay() {
        var s = Self.snapshot()
        let day = Self.date(2026, 4, 1)
        s.transactions = (0..<10).map { _ in Self.row(date: day, createdAt: day, isManualBalanceEdit: true) }
        #expect(AchievementEvaluator.balanceCheckCount(s) == 1)
        #expect(!Self.satisfied(s).contains("balance-check-10"))
    }

    @Test func balanceChecksAcrossDaysAndAccountsCount() {
        var s = Self.snapshot()
        // Five days × two accounts = ten distinct pairs.
        s.transactions = (0..<5).flatMap { index -> [TransactionFact] in
            let day = Self.calendar.date(byAdding: .day, value: index, to: Self.date(2026, 4, 1))!
            return ["main", "wallet"].map {
                Self.row(date: day, createdAt: day, isManualBalanceEdit: true, account: $0)
            }
        }
        #expect(Self.satisfied(s).contains("balance-check-10"))
    }

    // MARK: - Transfers & currencies

    @Test func anyTransferUnlocksFirstTransfer() {
        var s = Self.snapshot()
        let day = Self.date(2026, 4, 1)
        s.transactions = [Self.row(date: day, createdAt: day, isTransfer: true, destination: "savings")]
        #expect(Self.satisfied(s).contains("first-transfer"))
    }

    /// A second-currency account nobody ever uses is a decoy.
    @Test func multiCurrencyNeedsTransactionsInBothCurrencies() {
        var s = Self.snapshot()
        let day = Self.date(2026, 4, 1)
        s.accounts = [
            AccountFact(id: AnyHashable("main"), currencyCode: "ILS"),
            AccountFact(id: AnyHashable("dollars"), currencyCode: "USD"),
        ]
        s.transactions = [Self.row(date: day, createdAt: day, account: "main")]
        #expect(!Self.satisfied(s).contains("multi-currency"))

        // A transfer *into* the dollar account makes it a used account.
        s.transactions.append(Self.row(date: day, createdAt: day, isTransfer: true, destination: "dollars"))
        #expect(Self.satisfied(s).contains("multi-currency"))
    }

    // MARK: - Budget months

    /// A clean month: closed, after the epoch, budget settled beforehand,
    /// 15 real rows, under budget.
    private static func budgetSnapshot(months: [YearMonth], rowsPerMonth: Int = 15) -> AchievementSnapshot {
        var s = snapshot()
        s.budgetLastChangedAt = date(2025, 12, 20)
        s.transactions = months.flatMap { rows(in: $0, count: rowsPerMonth, entryDays: 5) }
        s.months = months.map { MonthFact(month: $0, isUnderBudget: true, isSurplus: false, wantsShare: 0.5) }
        return s
    }

    @Test func aCleanMonthUnderBudgetUnlocksTheFirstPatch() {
        let s = Self.budgetSnapshot(months: [YearMonth(year: 2026, month: 3)])
        #expect(Self.satisfied(s).contains("under-budget-1"))
        #expect(AchievementEvaluator.budgetMonthsMet(s) == [YearMonth(year: 2026, month: 3)])
    }

    /// Raising the budget on the 15th is exactly the farm the rule exists
    /// for — and an edit made *after* the month still counts, because past
    /// months are judged against today's plan.
    @Test func aBudgetEditedMidMonthDisqualifiesIt() {
        var s = Self.budgetSnapshot(months: [YearMonth(year: 2026, month: 3)])
        s.budgetLastChangedAt = Self.date(2026, 3, 15)
        #expect(!Self.satisfied(s).contains("under-budget-1"))
        #expect(AchievementEvaluator.budgetMonthsMet(s).isEmpty)

        s.budgetLastChangedAt = Self.date(2026, 4, 2)
        #expect(!Self.satisfied(s).contains("under-budget-1"))
    }

    @Test func monthsBeforeTheEpochAreNeverJudged() {
        let s = Self.budgetSnapshot(months: [YearMonth(year: 2025, month: 11)])
        #expect(AchievementEvaluator.budgetMonthsMet(s).isEmpty)
    }

    @Test func theCurrentMonthIsNotClosedYet() {
        let s = Self.budgetSnapshot(months: [YearMonth(year: 2026, month: 9)])
        #expect(AchievementEvaluator.budgetMonthsMet(s).isEmpty)
    }

    /// An empty month can't trivially "stay under budget".
    @Test func aThinMonthDoesNotQualify() {
        let s = Self.budgetSnapshot(months: [YearMonth(year: 2026, month: 3)], rowsPerMonth: 14)
        #expect(!Self.satisfied(s).contains("under-budget-1"))
    }

    @Test func consecutiveBudgetMonthsUnlockTheRun() {
        let months = (3...5).map { YearMonth(year: 2026, month: $0) }
        #expect(Self.satisfied(Self.budgetSnapshot(months: months)).contains("under-budget-3"))
    }

    @Test func wantsUnderThirtyPercentNeedsAQualifyingMonth() {
        var s = Self.budgetSnapshot(months: [YearMonth(year: 2026, month: 3)])
        s.months = [MonthFact(month: YearMonth(year: 2026, month: 3), isUnderBudget: false, isSurplus: false, wantsShare: 0.2)]
        #expect(Self.satisfied(s).contains("wants-under-30"))

        s.budgetLastChangedAt = Self.date(2026, 3, 10)
        #expect(!Self.satisfied(s).contains("wants-under-30"))
    }

    // MARK: - Consecutive runs

    @Test func aGapMonthBreaksTheRun() {
        let months = [
            YearMonth(year: 2026, month: 1),
            YearMonth(year: 2026, month: 2),
            YearMonth(year: 2026, month: 4),
        ]
        #expect(AchievementEvaluator.longestConsecutiveRun(months) == 2)
    }

    @Test func aRunCarriesAcrossTheNewYear() {
        let months = [
            YearMonth(year: 2025, month: 11),
            YearMonth(year: 2025, month: 12),
            YearMonth(year: 2026, month: 1),
        ]
        #expect(AchievementEvaluator.longestConsecutiveRun(months) == 3)
        #expect(AchievementEvaluator.longestConsecutiveRun([]) == 0)
    }

    // MARK: - Surplus months

    private static func surplusSnapshot(entryDays: Int) -> AchievementSnapshot {
        var s = snapshot()
        let months = (2...4).map { YearMonth(year: 2025, month: $0) }
        s.transactions = months.flatMap { rows(in: $0, count: 10, entryDays: entryDays) }
        s.months = months.map { MonthFact(month: $0, isUnderBudget: false, isSurplus: true, wantsShare: nil) }
        return s
    }

    /// History counts for surplus — no epoch — as long as it was logged
    /// over real days.
    @Test func threeLoggedSurplusMonthsUnlock() {
        #expect(Self.satisfied(Self.surplusSnapshot(entryDays: 8)).contains("surplus-3"))
    }

    @Test func surplusMonthsTypedInOneSittingDoNot() {
        #expect(!Self.satisfied(Self.surplusSnapshot(entryDays: 7)).contains("surplus-3"))
    }

    // MARK: - Deposits

    @Test func anEmptyDepositShellIsNotADeposit() {
        var s = Self.snapshot()
        s.deposits = [DepositFact(hasRate: true, hasMaturityDate: true, balance: 0, isPaidOut: false, isReplenishable: false, trancheEntryDates: [])]
        #expect(!Self.satisfied(s).contains("first-deposit"))

        s.deposits = [DepositFact(hasRate: true, hasMaturityDate: true, balance: 10_000, isPaidOut: false, isReplenishable: false, trancheEntryDates: [])]
        #expect(Self.satisfied(s).contains("first-deposit"))
    }

    @Test func aPaidOutDepositCountsAsMatured() {
        var s = Self.snapshot()
        s.deposits = [DepositFact(hasRate: true, hasMaturityDate: true, balance: 0, isPaidOut: true, isReplenishable: false, trancheEntryDates: [])]
        let ids = Self.satisfied(s)
        #expect(ids.contains("deposit-matured"))
        #expect(ids.contains("first-deposit"))
    }

    /// Ten rungs entered in one month is a burst, not a ladder.
    @Test func aLadderNeedsRungsAcrossFiveMonths() {
        var s = Self.snapshot()
        let burst = (0..<10).map { Self.date(2026, 3, $0 + 1) }
        s.deposits = [DepositFact(hasRate: true, hasMaturityDate: true, balance: 1, isPaidOut: false, isReplenishable: true, trancheEntryDates: burst)]
        #expect(!Self.satisfied(s).contains("ladder-10"))

        let spread = (0..<10).map { Self.date(2026, $0 % 5 + 1, 10) }
        s.deposits = [DepositFact(hasRate: true, hasMaturityDate: true, balance: 1, isPaidOut: false, isReplenishable: true, trancheEntryDates: spread)]
        #expect(Self.satisfied(s).contains("ladder-10"))
    }

    // MARK: - Goals

    @Test func aGoalCompletedTwentyNineDaysInIsTooQuick() {
        let created = Self.date(2026, 3, 1)
        let tooSoon = GoalFact(targetAmount: 1_000, createdAt: created, completedAt: Self.calendar.date(byAdding: .day, value: 29, to: created))
        let genuine = GoalFact(targetAmount: 1_000, createdAt: created, completedAt: Self.calendar.date(byAdding: .day, value: 30, to: created))
        #expect(!AchievementEvaluator.isGenuinelyCompleted(tooSoon, calendar: Self.calendar))
        #expect(AchievementEvaluator.isGenuinelyCompleted(genuine, calendar: Self.calendar))
    }

    @Test func aGoalMissingItsDatesCannotProveItself() {
        let legacy = GoalFact(targetAmount: 1_000, createdAt: nil, completedAt: Self.date(2026, 5, 1))
        #expect(!AchievementEvaluator.isGenuinelyCompleted(legacy, calendar: Self.calendar))
    }
}
