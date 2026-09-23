import Foundation

// MARK: - Plain-value facts

/// A calendar month, as a value that sorts and steps. Used to find
/// *consecutive* runs, where "the month after December 2026" has to be
/// January 2027.
struct YearMonth: Hashable, Comparable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(_ date: Date, calendar: Calendar) {
        let comps = calendar.dateComponents([.year, .month], from: date)
        self.init(year: comps.year ?? 2000, month: comps.month ?? 1)
    }

    var next: YearMonth {
        month == 12 ? YearMonth(year: year + 1, month: 1) : YearMonth(year: year, month: month + 1)
    }

    /// Midnight on the 1st, and midnight on the 1st of the following month.
    func start(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    func end(in calendar: Calendar) -> Date? {
        next.start(in: calendar)
    }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// One live transaction, reduced to what the achievements look at.
struct TransactionFact {
    /// When the money moved — user-chosen, so it only ever decides *which
    /// month* a row belongs to, never how spread out the logging was.
    let date: Date
    /// When the row was written. `nil` for rows that predate the field: they
    /// count toward totals but add no distinct entry day.
    let createdAt: Date?
    let isTransfer: Bool
    let isManualBalanceEdit: Bool
    let hasCategory: Bool
    /// Opaque account identities, so the pure layer never holds a model.
    let accountID: AnyHashable?
    let destinationAccountID: AnyHashable?

    /// A row the user logged as income or expense, as opposed to a transfer
    /// or the manual-balance bookkeeping marker.
    var isReal: Bool { !isTransfer && !isManualBalanceEdit }
}

/// One attachment on a live transaction.
struct AttachmentFact {
    let transactionID: AnyHashable
    let createdAt: Date
}

/// One live account.
struct AccountFact {
    let id: AnyHashable
    let currencyCode: String
}

/// One live savings account (deposit).
struct DepositFact {
    let hasRate: Bool
    let hasMaturityDate: Bool
    let balance: Decimal
    let isPaidOut: Bool
    let isReplenishable: Bool
    /// When each live sub-deposit was *entered* — `DepositTranche.createdAt`,
    /// not its user-chosen `startDate` (see `AchievementEvaluator.ladder`).
    let trancheEntryDates: [Date]
}

/// One goal.
struct GoalFact {
    let targetAmount: Decimal
    let createdAt: Date?
    let completedAt: Date?
}

/// A closed month's money verdicts, computed by `BudgetVsActual` (the
/// evaluator deliberately doesn't reimplement budget maths). Row counts and
/// entry spread are *not* here — the evaluator derives those itself from the
/// transaction facts, so the anti-farm floors are tested in one place.
struct MonthFact {
    let month: YearMonth
    /// A budget existed, nothing overran, and every figure converted.
    let isUnderBudget: Bool
    /// Income beat expenses (transfers and balance markers excluded).
    let isSurplus: Bool
    /// `.want` spend as a fraction of all spend; `nil` with no spend.
    let wantsShare: Double?
}

/// Everything the evaluator needs, as plain values. Built by
/// `ProgressService.evaluateAchievements` from the store; built by hand in
/// the tests.
struct AchievementSnapshot {
    var longestStreak: Int = 0
    var transactions: [TransactionFact] = []
    var attachments: [AttachmentFact] = []
    var accounts: [AccountFact] = []
    var deposits: [DepositFact] = []
    var goals: [GoalFact] = []
    var months: [MonthFact] = []
    /// The latest of every line's `lastEditedAt` and
    /// `UserProgress.budgetLastTouchedAt`; `nil` when neither was ever set.
    var budgetLastChangedAt: Date?
    var achievementsEpoch: Date
    var now: Date
    var calendar: Calendar = .current
}

// MARK: - The rules

/// Pure: a snapshot in, the set of satisfied achievement ids out.
///
/// Evaluates **facts, not the XP ledger** (ACHIEVEMENTS.md §5) — it checks
/// `longestStreak >= 7`, not whether `streak-7` was paid — so a user who did
/// something before achievements shipped still gets the patch.
///
/// Everything here is hand-entered data, so farming can't be *prevented*,
/// only made more effort than the honest path (§4): count distinct things
/// rather than rows, require entry spread over real days (`createdAt`),
/// require a substance floor per month, and require the budget to be settled
/// before the month it's judged on.
enum AchievementEvaluator {

    // MARK: Thresholds

    /// Row count and distinct entry days for each logging tier.
    static let loggingTiers: [(id: String, rows: Int, days: Int)] = [
        ("log-100", 100, 30),
        ("log-500", 500, 90),
        ("log-1000", 1_000, 180),
    ]

    /// A budget month needs this many real rows, so an empty month can't
    /// trivially "stay under budget".
    static let budgetMonthMinimumRows = 15
    /// A surplus month needs this many real rows, entered on this many days.
    static let surplusMonthMinimumRows = 10
    static let surplusMonthMinimumEntryDays = 8
    static let wantsShareCeiling = 0.30
    static let goalMinimumAgeDays = 30

    // MARK: Entry point

    static func satisfied(_ s: AchievementSnapshot) -> Set<String> {
        var ids: Set<String> = []
        func grant(_ id: String, if condition: Bool) {
            if condition { ids.insert(id) }
        }

        let cal = s.calendar
        let real = s.transactions.filter(\.isReal)

        // התמדה
        grant("streak-7", if: s.longestStreak >= 7)
        grant("streak-30", if: s.longestStreak >= 30)
        grant("streak-100", if: s.longestStreak >= 100)
        let realEntryDays = distinctDays(real.compactMap(\.createdAt), calendar: cal)
        for tier in loggingTiers {
            grant(tier.id, if: real.count >= tier.rows && realEntryDays >= tier.days)
        }

        // בקרה
        let budgetMonths = budgetMonthsMet(s)
        let longestUnder = longestConsecutiveRun(budgetMonths)
        grant("under-budget-1", if: longestUnder >= 1)
        grant("under-budget-3", if: longestUnder >= 3)
        grant("under-budget-12", if: longestUnder >= 12)
        grant("wants-under-30", if: s.months.contains { fact in
            guard let share = fact.wantsShare else { return false }
            return share < wantsShareCeiling && isBudgetQualifying(fact.month, in: s)
        })

        // צמיחה
        let longestSurplus = longestConsecutiveRun(surplusMonths(s))
        grant("surplus-3", if: longestSurplus >= 3)
        grant("surplus-6", if: longestSurplus >= 6)
        grant("surplus-12", if: longestSurplus >= 12)

        // חיסכון
        // A real deposit, not an empty shell: terms *and* money. One that has
        // already paid out was real by definition, even though it's at zero.
        grant("first-deposit", if: s.deposits.contains {
            $0.hasRate && $0.hasMaturityDate && ($0.balance > 0 || $0.isPaidOut)
        })
        grant("deposit-matured", if: s.deposits.contains(where: \.isPaidOut))
        grant("ladder-10", if: s.deposits.contains { isLadder($0, calendar: cal) })
        grant("first-goal", if: s.goals.contains { $0.targetAmount > 0 })
        grant("goal-done", if: s.goals.contains { isGenuinelyCompleted($0, calendar: cal) })

        // סדר
        let categorised = real.filter(\.hasCategory)
        grant("categorised-50", if: categorised.count >= 50
            && distinctDays(categorised.compactMap(\.createdAt), calendar: cal) >= 20)
        grant("first-attachment", if: !s.attachments.isEmpty)
        // Distinct *transactions*: 25 files on one receipt is still one receipt.
        let attachedTransactions = Set(s.attachments.map(\.transactionID))
        grant("attachments-25", if: attachedTransactions.count >= 25
            && distinctDays(s.attachments.map(\.createdAt), calendar: cal) >= 10)
        grant("balance-check-10", if: balanceCheckCount(s) >= 10)
        grant("first-transfer", if: s.transactions.contains(where: \.isTransfer))
        grant("multi-currency", if: activeCurrencyCount(s) >= 2)

        return ids
    }

    // MARK: Budget months

    /// Whether `month` may be judged at all (ACHIEVEMENTS.md §6, בקרה):
    /// closed, on or after the epoch, the budget untouched since before it
    /// began, and enough real rows to mean something.
    ///
    /// "Untouched" checks the budget as a *whole*, not only the lines that
    /// apply to the month: a line re-scheduled away from the month no longer
    /// "applies" to it, yet moving it changed that month's plan. And an edit
    /// made *after* the month still disqualifies it, because `BudgetVsActual`
    /// judges past months against the current plan — raising the budget in
    /// March would otherwise rescue February.
    static func isBudgetQualifying(_ month: YearMonth, in s: AchievementSnapshot) -> Bool {
        guard let start = month.start(in: s.calendar),
              let end = month.end(in: s.calendar),
              end <= s.now,
              start >= s.achievementsEpoch,
              (s.budgetLastChangedAt ?? .distantPast) < start
        else { return false }
        return realRows(in: month, s).count >= budgetMonthMinimumRows
    }

    /// Qualifying months that finished under budget, oldest first. Also what
    /// `XPReason.budgetMonthMet` pays for, once per month.
    static func budgetMonthsMet(_ s: AchievementSnapshot) -> [YearMonth] {
        s.months
            .filter { $0.isUnderBudget && isBudgetQualifying($0.month, in: s) }
            .map(\.month)
            .sorted()
    }

    // MARK: Surplus months

    /// Closed months where income beat expenses *and* the ledger behind the
    /// verdict is substantial: enough rows, entered on enough distinct days.
    /// No epoch here — unlike the budget rule, nothing about a surplus needed
    /// committing to in advance, so history counts.
    static func surplusMonths(_ s: AchievementSnapshot) -> [YearMonth] {
        s.months
            .filter { fact in
                guard fact.isSurplus,
                      let end = fact.month.end(in: s.calendar), end <= s.now
                else { return false }
                let rows = realRows(in: fact.month, s)
                return rows.count >= surplusMonthMinimumRows
                    && distinctDays(rows.compactMap(\.createdAt), calendar: s.calendar)
                        >= surplusMonthMinimumEntryDays
            }
            .map(\.month)
            .sorted()
    }

    // MARK: Helpers

    /// Real rows whose `date` falls in `month`.
    static func realRows(in month: YearMonth, _ s: AchievementSnapshot) -> [TransactionFact] {
        s.transactions.filter { $0.isReal && YearMonth($0.date, calendar: s.calendar) == month }
    }

    /// The longest run of calendar-consecutive months. A gap month breaks it.
    static func longestConsecutiveRun(_ months: [YearMonth]) -> Int {
        let sorted = Set(months).sorted()
        var longest = 0
        var current = 0
        var previous: YearMonth?
        for month in sorted {
            current = (previous?.next == month) ? current + 1 : 1
            longest = max(longest, current)
            previous = month
        }
        return longest
    }

    static func distinctDays(_ dates: [Date], calendar: Calendar) -> Int {
        Set(dates.map { calendar.startOfDay(for: $0) }).count
    }

    /// Manual balance corrections on distinct (account, day) pairs — at most
    /// one per account per day, so nudging one balance ten times in a row
    /// counts once.
    ///
    /// Falls back to `date` for a legacy row: the manual-balance marker's
    /// date is stamped by code at the moment of the edit, not picked by the
    /// user, so for this row type it *is* the entry time.
    static func balanceCheckCount(_ s: AchievementSnapshot) -> Int {
        struct Pair: Hashable {
            let account: AnyHashable
            let day: Date
        }
        let pairs = s.transactions.compactMap { tx -> Pair? in
            guard tx.isManualBalanceEdit, let account = tx.accountID else { return nil }
            return Pair(account: account, day: s.calendar.startOfDay(for: tx.createdAt ?? tx.date))
        }
        return Set(pairs).count
    }

    /// Currencies among live accounts that actually carry a live
    /// transaction — a decoy account opened in a second currency and never
    /// used doesn't count.
    static func activeCurrencyCount(_ s: AchievementSnapshot) -> Int {
        var used: Set<AnyHashable> = []
        for tx in s.transactions {
            if let id = tx.accountID { used.insert(id) }
            if let id = tx.destinationAccountID { used.insert(id) }
        }
        return Set(s.accounts.filter { used.contains($0.id) }.map(\.currencyCode)).count
    }

    /// One replenishable deposit with at least 10 live sub-deposits entered
    /// across at least 5 distinct months.
    ///
    /// Keyed on each rung's *entry* time (`DepositTranche.createdAt`) rather
    /// than the `startDate` ACHIEVEMENTS.md names: a rung's start date is the
    /// funding transfer's user-chosen `date`, so ten transfers back-dated
    /// across five months in one sitting would satisfy it — exactly the hole
    /// §4's doctrine says a `date`-based guard leaves open.
    static func isLadder(_ deposit: DepositFact, calendar: Calendar) -> Bool {
        guard deposit.isReplenishable, deposit.trancheEntryDates.count >= 10 else { return false }
        let months = Set(deposit.trancheEntryDates.map { YearMonth($0, calendar: calendar) })
        return months.count >= 5
    }

    /// Completed at least 30 days after it was created — blocks create-and-
    /// complete farming. A goal missing either date can't prove it.
    static func isGenuinelyCompleted(_ goal: GoalFact, calendar: Calendar) -> Bool {
        guard let created = goal.createdAt, let completed = goal.completedAt else { return false }
        let days = calendar.dateComponents([.day], from: created, to: completed).day ?? 0
        return days >= goalMinimumAgeDays
    }
}
