import Foundation

/// Income and spending per month or per year, spending split into needs and
/// wants — the data behind the analytics trend chart ("לאורך זמן").
///
/// Counted by the same rules as the rest of the analytics: manual balance
/// edits and transfers are neither income nor expense, and every amount is
/// converted into the preferred currency (a row without a rate is skipped
/// and flagged). Spending that isn't a want — needs, the neutral categories
/// and uncategorised rows — counts as a need, so the two stacked parts always
/// add up to the whole expense — neutral spending already counts toward
/// צרכים on the dashboard's budget card.
///
/// The points are **contiguous**: every month (or year) from the first one
/// with a transaction to the current one is there, empty ones as zero, so a
/// quiet month reads as a gap in the chart rather than silently vanishing.
struct MoneyFlowSeries: Equatable {
    enum Granularity: String, CaseIterable, Identifiable {
        case month
        case year

        var id: Self { self }

        fileprivate var component: Calendar.Component {
            self == .month ? .month : .year
        }
    }

    struct Point: Identifiable, Equatable {
        /// The first instant of the month or year.
        let start: Date
        var income: Decimal = 0
        var needs: Decimal = 0
        var wants: Decimal = 0

        var id: Date { start }
        var expense: Decimal { needs + wants }
        var net: Decimal { income - expense }
    }

    let granularity: Granularity
    /// Oldest first, ending at the current period (or a later one, if a
    /// transaction is dated in the future).
    let points: [Point]
    let fxUnavailable: Bool

    /// Months are Gregorian, as the budget's are: a device set to the Hebrew
    /// calendar would otherwise bucket by Hebrew months.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    init(
        transactions: [Transaction],
        granularity: Granularity,
        preferredCurrency: String,
        fxSnapshot: FXRateSnapshot?,
        calendar: Calendar = MoneyFlowSeries.calendar,
        now: Date = .now
    ) {
        self.granularity = granularity
        let component = granularity.component
        var buckets: [Date: Point] = [:]
        var fxMissing = false

        for tx in transactions where !tx.isManualBalanceEdit && !tx.isTransfer {
            guard let start = calendar.dateInterval(of: component, for: tx.date)?.start else { continue }
            let value: Decimal
            if tx.currencyCode == preferredCurrency {
                value = tx.amount
            } else if let fxSnapshot,
                      let converted = CurrencyConverter.convert(tx.amount, from: tx.currencyCode, to: preferredCurrency, using: fxSnapshot) {
                value = converted
            } else {
                fxMissing = true
                continue
            }

            var point = buckets[start] ?? Point(start: start)
            switch tx.kind {
            case .income:
                point.income += value
            case .expense:
                if tx.category?.nature == .want {
                    point.wants += value
                } else {
                    point.needs += value
                }
            }
            buckets[start] = point
        }

        self.fxUnavailable = fxMissing
        guard let first = buckets.keys.min(),
              let current = calendar.dateInterval(of: component, for: now)?.start
        else {
            self.points = []
            return
        }

        // Walk period by period from the first to the last, filling gaps.
        let last = max(current, buckets.keys.max() ?? current)
        var points: [Point] = []
        var cursor = first
        while cursor <= last {
            points.append(buckets[cursor] ?? Point(start: cursor))
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            cursor = next
        }
        self.points = points
    }

    /// The figures for the month (or year) containing `date`: its point, or
    /// an empty one when the date falls outside the history (a period picked
    /// before the first entry) — "nothing that month", not "no answer".
    func summary(for date: Date, calendar: Calendar = MoneyFlowSeries.calendar) -> Point? {
        if let point = point(containing: date, calendar: calendar) { return point }
        guard let start = calendar.dateInterval(of: granularity.component, for: date)?.start else { return nil }
        return Point(start: start)
    }

    /// The point whose month (or year) contains `date` — what a tap on the
    /// chart selects, since the chart reports the raw date under the finger.
    func point(containing date: Date, calendar: Calendar = MoneyFlowSeries.calendar) -> Point? {
        guard let start = calendar.dateInterval(of: granularity.component, for: date)?.start else { return nil }
        return points.first { $0.start == start }
    }
}
