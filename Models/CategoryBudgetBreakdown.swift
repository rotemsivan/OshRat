import Foundation
import SwiftData

/// The whole budget for a period, category by category — the analytics
/// station that turns the dashboard's "you're over budget" into *where*.
///
/// The dashboard card (`BudgetVsActual`) rolls everything into needs / wants
/// buckets, which is right for a glance but hides the answer to "which
/// category did it?". This keeps the same counting rules and just doesn't
/// roll up: each expense category gets its planned figure (every budget line
/// of it, `plannedAmount(inMonth:year:)` summed over the period's months) and
/// its actual (every real expense of it in the period). It's the
/// `CategoryBudgetStatus` sum for every category at once, over a month *or* a
/// year.
///
/// Spending in a category nobody budgeted for is kept apart
/// (`unbudgeted`) rather than scored against zero — it isn't an overrun of
/// anything, but it is part of the full picture, and it does count toward
/// the total.
///
/// Pure and SwiftUI-free, compiled into the test targets
/// (`OshRatTests/CategoryBudgetBreakdownTests.swift`).
struct CategoryBudgetBreakdown {
    let currencyCode: String
    /// Budgeted expense categories: overruns first (largest overrun first),
    /// then by how much of the plan is used.
    let rows: [CategoryBudgetRow]
    /// Expense categories with spending and no plan, biggest first.
    let unbudgeted: [CategoryBudgetRow]
    let plannedIncome: Decimal
    let actualIncome: Decimal
    /// How much of the period has gone by, 0...1, while it's running; `nil`
    /// once it's over. The station draws it as a pace mark on every bar.
    let elapsedFraction: Double?
    /// Whether the user has any budget lines at all, in any period.
    let hasAnyBudget: Bool
    let fxUnavailable: Bool

    var plannedExpense: Decimal { rows.reduce(0) { $0 + $1.planned } }
    /// Everything spent — budgeted categories and unbudgeted ones.
    var actualExpense: Decimal { rows.reduce(0) { $0 + $1.actual } + unbudgetedTotal }
    var unbudgetedTotal: Decimal { unbudgeted.reduce(0) { $0 + $1.actual } }

    var overruns: [CategoryBudgetRow] { rows.filter(\.isOver) }

    /// Over the whole expense plan. Gated on a plan, as the dashboard's is.
    var isTotalOver: Bool { plannedExpense > 0 && actualExpense > plannedExpense }

    var hasPlanInPeriod: Bool { plannedExpense > 0 || plannedIncome > 0 }

    var expenseFraction: Double {
        plannedExpense > 0 ? NSDecimalNumber(decimal: actualExpense / plannedExpense).doubleValue : 0
    }
}

/// One expense category's plan against reality in the period.
struct CategoryBudgetRow: Identifiable {
    let id: CategoryKey
    let name: String
    let colorHex: String
    let symbolName: String
    let planned: Decimal
    let actual: Decimal

    /// Actual as a share of planned — can pass 1. Zero with nothing planned.
    var fraction: Double {
        planned > 0 ? NSDecimalNumber(decimal: actual / planned).doubleValue : 0
    }
    var isOver: Bool { planned > 0 && actual > planned }
    var overAmount: Decimal { max(actual - planned, 0) }
    var remaining: Decimal { max(planned - actual, 0) }
}

// MARK: - Building

extension CategoryBudgetBreakdown {

    /// - Parameters:
    ///   - interval: the period — a month or a year. Its months are read in
    ///     `calendar`, which must be the one `BudgetItem`'s month numbers mean
    ///     (Gregorian).
    ///   - now: marks the pace while `interval` contains it.
    init(
        budgetItems: [BudgetItem],
        transactions: [Transaction],
        interval: DateInterval,
        preferredCurrency: String,
        fxSnapshot: FXRateSnapshot?,
        calendar: Calendar,
        now: Date = .now
    ) {
        var fxMissing = false
        func convert(_ amount: Decimal, _ code: String) -> Decimal? {
            if code == preferredCurrency { return amount }
            guard let fxSnapshot,
                  let value = CurrencyConverter.convert(amount, from: code, to: preferredCurrency, using: fxSnapshot)
            else {
                fxMissing = true
                return nil
            }
            return value
        }

        // Every (month, year) the interval covers — one for a month, twelve
        // for a year — so a yearly bill lands in the year's plan exactly once.
        var months: [(month: Int, year: Int)] = []
        var cursor = interval.start
        while cursor < interval.end {
            let comps = calendar.dateComponents([.month, .year], from: cursor)
            if let month = comps.month, let year = comps.year { months.append((month, year)) }
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }

        var planned: [CategoryKey: (amount: Decimal, category: Category?)] = [:]
        var actual: [CategoryKey: (amount: Decimal, category: Category?)] = [:]
        var plannedIncome = Decimal(0)
        var actualIncome = Decimal(0)

        for item in budgetItems {
            var total = Decimal(0)
            for (month, year) in months {
                let amount = item.plannedAmount(inMonth: month, year: year)
                guard amount != 0, let converted = convert(amount, item.currencyCode) else { continue }
                total += converted
            }
            guard total != 0 else { continue }
            switch item.kind {
            case .income:
                plannedIncome += total
            case .expense:
                let key = CategoryKey(item.category)
                planned[key, default: (0, item.category)].amount += total
            }
        }

        for tx in transactions where !tx.isTransfer && !tx.isManualBalanceEdit {
            // Half-open: the first instant of the next period isn't this one.
            guard interval.contains(tx.date), tx.date < interval.end,
                  let converted = convert(tx.amount, tx.currencyCode) else { continue }
            switch tx.kind {
            case .income:
                actualIncome += converted
            case .expense:
                let key = CategoryKey(tx.category)
                actual[key, default: (0, tx.category)].amount += converted
            }
        }

        func row(_ key: CategoryKey, category: Category?) -> CategoryBudgetRow {
            CategoryBudgetRow(
                id: key,
                name: category?.name ?? CategoryKey.uncategorisedName,
                colorHex: category?.colorHex ?? "#9E9E9E",
                symbolName: category?.symbolName ?? "questionmark",
                planned: planned[key]?.amount ?? 0,
                actual: actual[key]?.amount ?? 0
            )
        }

        self.rows = planned
            .map { row($0.key, category: $0.value.category) }
            .sorted { lhs, rhs in
                if lhs.isOver != rhs.isOver { return lhs.isOver }
                if lhs.isOver, lhs.overAmount != rhs.overAmount { return lhs.overAmount > rhs.overAmount }
                if lhs.fraction != rhs.fraction { return lhs.fraction > rhs.fraction }
                return lhs.name < rhs.name
            }
        self.unbudgeted = actual
            .filter { planned[$0.key] == nil && $0.value.amount > 0 }
            .map { row($0.key, category: $0.value.category) }
            .sorted { $0.actual != $1.actual ? $0.actual > $1.actual : $0.name < $1.name }

        if interval.contains(now), now < interval.end, interval.duration > 0 {
            self.elapsedFraction = now.timeIntervalSince(interval.start) / interval.duration
        } else {
            self.elapsedFraction = nil
        }

        self.currencyCode = preferredCurrency
        self.plannedIncome = plannedIncome
        self.actualIncome = actualIncome
        self.hasAnyBudget = !budgetItems.isEmpty
        self.fxUnavailable = fxMissing
    }
}
