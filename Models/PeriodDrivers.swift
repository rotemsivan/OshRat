import Foundation
import SwiftData

/// *Why* one period's money differs from the one before it — the station that
/// follows "מול החודש הקודם" on the analytics roadmap and explains its numbers.
///
/// It answers three questions, each from the same two windows of real
/// transactions (transfers and manual balance edits left out, as everywhere):
///   * **Where** — every category's movement, biggest swing first
///     (`Side.categories`).
///   * **How** — the number of purchases and the average one, in each window
///     (`Side.currentCount`, `currentAverage`, …).
///   * **What stood out** — the period's unusually large single expenses
///     (`notableExpenses`), the one-offs a category total would hide. A big
///     bill that simply comes every month (rent, the kindergarten) is not
///     news, so a purchase logged from a budget line, or matched by a similar
///     one in the same category last period, is never "notable".
///
/// Pure and SwiftUI-free, compiled into the test targets
/// (`OshRatTests/PeriodDriversTests.swift`). Everything is converted into the
/// preferred currency; a row with no FX rate is skipped and flagged.
struct PeriodDrivers {
    let currencyCode: String
    let expense: Side
    let income: Side
    /// The current window's standout purchases, biggest first (at most three).
    let notableExpenses: [NotableExpense]
    let fxUnavailable: Bool

    /// Whether there's anything to compare against at all.
    var hasBaseline: Bool { expense.previous > 0 || income.previous > 0 }
}

// MARK: - Supporting value types

extension PeriodDrivers {

    /// One direction of money (income or expense) across the two windows.
    struct Side {
        let current: Decimal
        let previous: Decimal
        let currentCount: Int
        let previousCount: Int
        /// Every category that moved, biggest absolute change first.
        /// Categories that didn't change at all are left out.
        let categories: [CategoryDelta]

        var delta: Decimal { current - previous }

        var currentAverage: Decimal? { currentCount > 0 ? current / Decimal(currentCount) : nil }
        var previousAverage: Decimal? { previousCount > 0 ? previous / Decimal(previousCount) : nil }

        /// Signed change as a fraction of the previous total (-0.2 == 20% less);
        /// `nil` with no previous total to divide by.
        var changeFraction: Double? {
            guard previous > 0 else { return nil }
            return NSDecimalNumber(decimal: delta / previous).doubleValue
        }
    }

    /// A single purchase big enough to explain a month on its own.
    struct NotableExpense: Identifiable {
        let id: PersistentIdentifier
        let title: String
        let symbolName: String
        let colorHex: String
        let amount: Decimal
    }
}

/// Identifies a category across windows without leaning on its (editable,
/// possibly duplicated) name. Rows with no category share one bucket.
enum CategoryKey: Hashable {
    case category(PersistentIdentifier)
    case uncategorised

    init(_ category: Category?) {
        if let category {
            self = .category(category.persistentModelID)
        } else {
            self = .uncategorised
        }
    }

    /// The label a missing category reads as — the same one `AnalyticsReport` uses.
    static let uncategorisedName = "ללא קטגוריה"
}

/// One category's total in the current window against the previous one.
struct CategoryDelta: Identifiable {
    let id: CategoryKey
    let name: String
    let colorHex: String
    let symbolName: String
    let current: Decimal
    let previous: Decimal

    var delta: Decimal { current - previous }
}

// MARK: - Comparison windows

extension PeriodDrivers {

    /// The pair of date ranges a comparison should read.
    struct Windows: Equatable {
        let current: DateInterval
        let previous: DateInterval
        /// True when the current period is still running and both windows were
        /// cut to the days it has had so far.
        let isPartial: Bool
        /// Whole days compared in each window when partial (today included).
        let elapsedDays: Int?
    }

    /// Like-for-like windows for comparing `current` against `previous`.
    ///
    /// A finished period is compared whole. The **live** period is compared
    /// only over the days it has had — Sept 1–27 against Aug 1–27 — because a
    /// month that is 27 days old against a whole previous month always looks
    /// like "spending dropped", and would make the drivers explain a fall that
    /// is really just the calendar. Windows are whole days and half-open,
    /// like the transaction filters'; the previous one is clamped to its own
    /// end (March 31 compares with all of February).
    static func windows(
        current: DateInterval,
        previous: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> Windows {
        guard current.contains(now),
              let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        else {
            return Windows(current: current, previous: previous, isPartial: false, elapsedDays: nil)
        }
        let days = calendar.dateComponents([.day], from: current.start, to: endOfToday).day ?? 0
        let currentEnd = min(endOfToday, current.end)
        let previousEnd = min(
            calendar.date(byAdding: .day, value: days, to: previous.start) ?? previous.end,
            previous.end
        )
        return Windows(
            current: DateInterval(start: current.start, end: currentEnd),
            previous: DateInterval(start: previous.start, end: previousEnd),
            isPartial: true,
            elapsedDays: days
        )
    }
}

// MARK: - Building

extension PeriodDrivers {

    /// A purchase is "notable" when it's at least this many times the window's
    /// median expense…
    static let notableMedianMultiple: Decimal = 3
    /// …and at least this share of the window's total spend. The two together
    /// keep a quiet month's ₪90 dinner (3× a ₪30 median) off the list.
    static let notableMinimumShare: Decimal = 0.1
    /// Fewer expenses than this and there's no "usual" to stand out from.
    static let notableMinimumCount = 4
    /// A previous-period expense in the same category within this share of
    /// the amount makes a purchase a repeat, not a one-off.
    static let recurringTolerance: Decimal = 0.15

    init(
        transactions: [Transaction],
        windows: Windows,
        preferredCurrency: String,
        fxSnapshot: FXRateSnapshot?
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

        /// Running totals for one side, keyed by category.
        struct Tally {
            var current = Decimal(0), previous = Decimal(0)
            var currentCount = 0, previousCount = 0
            var byCategory: [CategoryKey: (current: Decimal, previous: Decimal, category: Category?)] = [:]

            mutating func add(_ value: Decimal, category: Category?, isCurrent: Bool) {
                let key = CategoryKey(category)
                var entry = byCategory[key] ?? (0, 0, category)
                if isCurrent {
                    current += value; currentCount += 1; entry.current += value
                } else {
                    previous += value; previousCount += 1; entry.previous += value
                }
                byCategory[key] = entry
            }

            var side: Side {
                let deltas = byCategory
                    .map { key, entry in
                        CategoryDelta(
                            id: key,
                            name: entry.category?.name ?? CategoryKey.uncategorisedName,
                            colorHex: entry.category?.colorHex ?? "#9E9E9E",
                            symbolName: entry.category?.symbolName ?? "questionmark",
                            current: entry.current,
                            previous: entry.previous
                        )
                    }
                    .filter { $0.delta != 0 }
                    // Name as the tie-break, so equal swings don't reshuffle
                    // between renders (dictionary order isn't stable).
                    .sorted { (lhs: CategoryDelta, rhs: CategoryDelta) -> Bool in
                        let left = abs(lhs.delta), right = abs(rhs.delta)
                        if left != right { return left > right }
                        return lhs.name < rhs.name
                    }
                return Side(
                    current: current, previous: previous,
                    currentCount: currentCount, previousCount: previousCount,
                    categories: deltas
                )
            }
        }

        var expenses = Tally()
        var incomes = Tally()
        var currentExpenses: [(tx: Transaction, value: Decimal)] = []
        var previousExpenses: [CategoryKey: [Decimal]] = [:]

        for tx in transactions where !tx.isTransfer && !tx.isManualBalanceEdit {
            let isCurrent: Bool
            if windows.current.contains(tx.date) {
                isCurrent = true
            } else if windows.previous.contains(tx.date) {
                isCurrent = false
            } else {
                continue
            }
            // `DateInterval.contains` includes `end`; the windows are half-open.
            if isCurrent ? tx.date == windows.current.end : tx.date == windows.previous.end { continue }
            guard let value = convert(tx.amount, tx.currencyCode) else { continue }
            switch tx.kind {
            case .income:
                incomes.add(value, category: tx.category, isCurrent: isCurrent)
            case .expense:
                expenses.add(value, category: tx.category, isCurrent: isCurrent)
                if isCurrent {
                    currentExpenses.append((tx, value))
                } else {
                    previousExpenses[CategoryKey(tx.category), default: []].append(value)
                }
            }
        }

        self.currencyCode = preferredCurrency
        self.expense = expenses.side
        self.income = incomes.side
        self.notableExpenses = Self.notable(
            in: currentExpenses, total: expenses.current, previous: previousExpenses
        )
        self.fxUnavailable = fxMissing
    }

    private static func notable(
        in expenses: [(tx: Transaction, value: Decimal)],
        total: Decimal,
        previous: [CategoryKey: [Decimal]]
    ) -> [NotableExpense] {
        guard expenses.count >= notableMinimumCount, total > 0 else { return [] }
        let sorted = expenses.map(\.value).sorted()
        let mid = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        let threshold = max(median * notableMedianMultiple, total * notableMinimumShare)

        func isRecurring(_ entry: (tx: Transaction, value: Decimal)) -> Bool {
            if entry.tx.budgetItem != nil { return true }
            let tolerance = entry.value * recurringTolerance
            return previous[CategoryKey(entry.tx.category)]?
                .contains { abs($0 - entry.value) <= tolerance } ?? false
        }

        return expenses
            .filter { $0.value >= threshold && !isRecurring($0) }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { entry in
                let tx = entry.tx
                let categoryName = tx.category?.name ?? CategoryKey.uncategorisedName
                let title = tx.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return NotableExpense(
                    id: tx.persistentModelID,
                    title: title.isEmpty ? categoryName : title,
                    symbolName: tx.category?.symbolName ?? "questionmark",
                    colorHex: tx.category?.colorHex ?? "#9E9E9E",
                    amount: entry.value
                )
            }
    }
}
