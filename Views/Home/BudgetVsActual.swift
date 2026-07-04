import Foundation

/// A pure, testable comparison of the current period's plan against what
/// actually happened — the data behind the merged dashboard card (and, later,
/// an Analytics station). The period is either *this month* (the default) or
/// *this year*, matching the Analytics חודש/שנה toggle.
///
/// It rolls every budget line's contribution to the period and every real
/// transaction inside it into three buckets — **income**, **needs**,
/// **wants** — each carrying both its planned figure and its actual figure in
/// the user's preferred currency. From those it derives whether the user has
/// gone over budget, by how much, and in which buckets.
///
/// There is no SwiftUI here on purpose: it's just numbers, so it can be
/// unit-tested and reused without dragging a view in. The bucketing rules are
/// kept identical to the old planned/actual cards so the merge changes nothing
/// about *what* the figures mean — only how they're shown:
///   * Income lines/transactions → `income`.
///   * Expenses classified `.want` → `wants`.
///   * Everything else expense (`.need`, `.neutral`, or uncategorised) →
///     `needs`, so an unclassified line is never silently dropped and lands in
///     the *same* bucket on both the planned and actual sides.
struct BudgetVsActual {

    let currencyCode: String

    let income: BudgetLine
    let needs: BudgetLine
    let wants: BudgetLine

    /// Whether the user has any budget lines at all. Drives the card's empty
    /// state vs. the "actuals only" fallback (activity but no plan to compare).
    let hasAnyBudget: Bool
    /// Whether any real income/expense was logged this month.
    let hasAnyActivity: Bool

    /// True when at least one figure was dropped for lack of an FX rate —
    /// lets the card show the same "FX unavailable" note the other cards use.
    let fxUnavailable: Bool
    /// Whether any contributing budget line or this-month transaction is in a
    /// currency other than the preferred one (so the FX note is even relevant).
    let hasCrossCurrency: Bool
    /// True when this month carries a non-recurring scheduled line (a yearly
    /// bill, a one-off gift) that won't be there next month — the card flags it
    /// so the planned total never reads as wrong without context.
    let hasScheduledExtras: Bool

    // MARK: - Derived

    var expenseLines: [BudgetLine] { [needs, wants] }

    var totalPlannedExpense: Decimal { needs.planned + wants.planned }
    var totalActualExpense: Decimal { needs.actual + wants.actual }

    /// Bottom line actually realised this month (income minus all spending).
    var actualNet: Decimal { income.actual - totalActualExpense }
    /// Bottom line the plan projected for the month.
    var plannedNet: Decimal { income.planned - totalPlannedExpense }

    /// Over the *total* expense budget. Gated on a non-zero plan so a user
    /// who hasn't budgeted is never told they "overran".
    var isTotalOverBudget: Bool {
        totalPlannedExpense > 0 && totalActualExpense > totalPlannedExpense
    }

    var totalOverAmount: Decimal { max(0, totalActualExpense - totalPlannedExpense) }

    /// Expense buckets that had a budget and exceeded it. (A bucket with no
    /// budget can't "overrun its budget" on its own — but it still counts
    /// toward `isTotalOverBudget`.)
    var individualOverruns: [BudgetLine] {
        expenseLines.filter { $0.planned > 0 && $0.actual > $0.planned }
    }

    /// The user is over budget when either the total expense plan is blown or
    /// a single budgeted category is. (Per the chosen "both, with detail" rule.)
    var hasOverrun: Bool { isTotalOverBudget || !individualOverruns.isEmpty }

    /// Everything the overrun pop-up / banner needs, or `nil` when on budget.
    var overrunSummary: OverrunSummary? {
        guard hasOverrun else { return nil }
        return OverrunSummary(
            lines: individualOverruns,
            totalPlanned: totalPlannedExpense,
            totalActual: totalActualExpense,
            isTotalOver: isTotalOverBudget
        )
    }
}

// MARK: - Supporting value types

/// One bucket's plan vs. reality. `planned`/`actual` are already in the
/// preferred currency; the rest is derived.
struct BudgetLine: Identifiable {
    enum Bucket: String {
        case income, needs, wants

        /// Hebrew label used in the overrun message and accessibility text.
        /// (The card uses its own `LocalizedStringKey` for the visible rows.)
        var hebrewLabel: String {
            switch self {
            case .income: return "הכנסות"
            case .needs:  return "צרכים"
            case .wants:  return "רצונות"
            }
        }

        /// Income going "over plan" is a good thing, not an overrun — only
        /// the two expense buckets are scored against their budget.
        var countsAsExpense: Bool { self != .income }
    }

    let bucket: Bucket
    let planned: Decimal
    let actual: Decimal

    var id: String { bucket.rawValue }

    /// Actual as a fraction of planned (0.91 == 91% of plan used). `nil`
    /// when nothing was planned, since the ratio is undefined.
    var progress: Double? {
        guard planned > 0 else { return nil }
        return (actual as NSDecimalNumber).doubleValue / (planned as NSDecimalNumber).doubleValue
    }

    /// This bucket had a budget and exceeded it.
    var isOverBudget: Bool { bucket.countsAsExpense && planned > 0 && actual > planned }

    /// Spending happened in a bucket that wasn't budgeted at all.
    var isUnbudgetedSpend: Bool { bucket.countsAsExpense && planned == 0 && actual > 0 }

    /// How far over its own budget this bucket ran (0 when not over).
    var overAmount: Decimal { isOverBudget ? actual - planned : 0 }
}

/// Snapshot of an overrun, shared by the inline banner and the alert.
struct OverrunSummary {
    /// Budgeted expense buckets that individually went over.
    let lines: [BudgetLine]
    let totalPlanned: Decimal
    let totalActual: Decimal
    /// Whether the *total* expense budget (not just a category) was blown.
    let isTotalOver: Bool

    var totalOverAmount: Decimal { max(0, totalActual - totalPlanned) }
}

// MARK: - Building the comparison

extension BudgetVsActual {

    /// Crunches the raw model objects into the comparison. The period is the
    /// `scope`-sized window (month or year) containing `now` — pass an
    /// arbitrary anchor date to report on a past or future period (the
    /// dashboard carousel does), or leave the defaults for "this month".
    /// `calendar` and `now` are also how tests pin a deterministic "today".
    init(
        budgetItems: [BudgetItem],
        transactions: [Transaction],
        preferredCurrency: String,
        fxSnapshot: FXRateSnapshot?,
        scope: AnalyticsPeriod.Scope = .month,
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        var fxMissing = false

        // One funnel for every conversion so the missing-rate flag flips
        // consistently — same pattern as `AnalyticsReport`.
        func convert(_ amount: Decimal, _ code: String) -> Decimal? {
            if code == preferredCurrency { return amount }
            guard let fxSnapshot,
                  let value = CurrencyConverter.convert(
                    amount, from: code, to: preferredCurrency, using: fxSnapshot
                  ) else {
                fxMissing = true
                return nil
            }
            return value
        }

        let comps = calendar.dateComponents([.month, .year], from: now)
        let month = comps.month ?? 1
        let year = comps.year ?? 2000
        /// The months the plan side sums over: just the current one, or every
        /// month of the current year. `plannedAmount(inMonth:year:)` already
        /// attributes each line to its right months, so the yearly figure is
        /// simply the twelve monthly contributions added up.
        let plannedMonths: [Int] = scope == .month ? [month] : Array(1...12)

        // MARK: Planned — each line's contribution to the period, bucketed.

        var plannedIncome = Decimal(0)
        var plannedNeeds = Decimal(0)
        var plannedWants = Decimal(0)
        for item in budgetItems {
            for plannedMonth in plannedMonths {
                let monthly = item.plannedAmount(inMonth: plannedMonth, year: year)
                guard monthly != 0, let converted = convert(monthly, item.currencyCode) else { continue }
                switch item.kind {
                case .income:
                    plannedIncome += converted
                case .expense:
                    if item.category?.nature == .want {
                        plannedWants += converted
                    } else {
                        plannedNeeds += converted   // need + neutral/none lean into needs
                    }
                }
            }
        }

        // MARK: Actual — the period's real transactions, bucketed identically.

        let periodInterval = calendar.dateInterval(
            of: scope == .month ? .month : .year, for: now
        )

        func isInPeriodReal(_ tx: Transaction) -> Bool {
            guard let periodInterval, periodInterval.contains(tx.date) else { return false }
            // Manual balance-edit rows and transfers are bookkeeping, not
            // income/expense — excluded exactly like the other dashboard cards.
            return !tx.isManualBalanceEdit && !tx.isTransfer
        }

        var actualIncome = Decimal(0)
        var actualNeeds = Decimal(0)
        var actualWants = Decimal(0)
        for tx in transactions where isInPeriodReal(tx) {
            guard let converted = convert(tx.amount, tx.currencyCode) else { continue }
            switch tx.kind {
            case .income:
                actualIncome += converted
            case .expense:
                if tx.category?.nature == .want {
                    actualWants += converted
                } else {
                    actualNeeds += converted
                }
            }
        }

        // MARK: Flags

        let crossBudget = budgetItems.contains { $0.currencyCode != preferredCurrency }
        let crossTx = transactions.contains { isInPeriodReal($0) && $0.currencyCode != preferredCurrency }

        // MARK: Assign

        self.currencyCode = preferredCurrency
        self.income = BudgetLine(bucket: .income, planned: plannedIncome, actual: actualIncome)
        self.needs = BudgetLine(bucket: .needs, planned: plannedNeeds, actual: actualNeeds)
        self.wants = BudgetLine(bucket: .wants, planned: plannedWants, actual: actualWants)
        self.hasAnyBudget = !budgetItems.isEmpty
        self.hasAnyActivity = actualIncome > 0 || actualNeeds > 0 || actualWants > 0
        self.hasCrossCurrency = crossBudget || crossTx
        self.hasScheduledExtras = budgetItems.contains { item in
            !item.landsEveryMonth
                && plannedMonths.contains { item.appliesTo(month: $0, year: year) }
        }
        // Set last so every `convert` call above has had its chance to flip it.
        self.fxUnavailable = fxMissing
    }
}
