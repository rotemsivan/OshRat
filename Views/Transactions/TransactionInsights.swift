import Foundation
import SwiftData

/// A pure, testable summary of what we can infer about a single transaction
/// from the rest of the ledger — "how often does this happen, is it on a
/// schedule, how does this one compare, and what are the related rows?".
///
/// There's no SwiftUI here on purpose (same philosophy as `AnalyticsReport`):
/// it's just numbers and enums, so it can be unit-tested and reused without
/// dragging a view in. Hebrew phrasing of these facts lives in the card view
/// that renders them, not here.
///
/// Everything is derived from *similar* transactions, where "similar" means
/// the same recurrence key (see `recurrenceKey`) — typically the same title,
/// or the same category when there's no title — and the same income/expense
/// kind. Transfers and manual balance-edit rows never participate.
struct TransactionInsights {
    /// How many transactions share this one's recurrence key, including
    /// itself. `1` means "first time we've seen this".
    let occurrenceCount: Int

    /// Other rows sharing the key, newest first, capped for display. The
    /// card lists these as "תנועות דומות".
    let similar: [Transaction]

    /// Detected recurrence, or `nil` when there are too few/too irregular
    /// occurrences to claim a schedule.
    let cadence: Cadence?

    /// Mean amount across same-currency occurrences (including this one).
    /// `nil` when there's nothing to average. Same-currency only — mixing
    /// currencies would need FX, which this value type deliberately avoids.
    let averageAmount: Decimal?

    /// This amount relative to the average of the *other* occurrences, as a
    /// signed fraction (`-0.12` == "12% cheaper than usual"). `nil` for a
    /// first occurrence or when the baseline average is zero.
    let amountDeltaFraction: Double?

    /// The most recent prior occurrence's date (strictly before this row),
    /// or `nil` if this is the earliest. The card shows it as "נראה
    /// לאחרונה לפני X ימים".
    let lastOccurrence: Date?

    /// A dominant day-of-week / part-of-month tendency, emitted only when
    /// there's a clear majority. `nil` when the timing looks scattered.
    let dayPattern: DayPattern?

    /// Whether there's anything worth showing an "תובנות" section for. A
    /// lone first-time transaction has nothing to say.
    var hasMeaningfulInsights: Bool {
        occurrenceCount > 1 || cadence != nil || dayPattern != nil
    }
}

// MARK: - Supporting enums

/// How regularly a transaction recurs. Named buckets are emitted only when
/// the gaps between occurrences are consistent enough; otherwise the cadence
/// is reported as `.irregular` carrying the average gap so the card can still
/// say "בערך כל N ימים".
enum Cadence: Equatable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly
    case irregular(averageDays: Int)
}

/// A timing tendency across a transaction's occurrences. Weekend is checked
/// against the Israeli week (Friday + Saturday); the part-of-month cases split
/// the month into thirds.
enum DayPattern: Equatable {
    case weekend
    case startOfMonth   // days 1–10
    case midMonth       // 11–20
    case endOfMonth     // 21+
}

// MARK: - Building the insights

extension TransactionInsights {

    /// Crunch the ledger into insights for one transaction. `calendar` is
    /// injectable so tests can pin a deterministic week/month layout.
    static func make(
        for transaction: Transaction,
        in all: [Transaction],
        calendar: Calendar = .current
    ) -> TransactionInsights {
        // A transfer / manual-edit row, or one with neither title nor
        // category, has no recurrence group — return the "first time,
        // nothing to say" shape.
        guard let key = recurrenceKey(for: transaction) else {
            return TransactionInsights(
                occurrenceCount: 1, similar: [], cadence: nil,
                averageAmount: nil, amountDeltaFraction: nil,
                lastOccurrence: nil, dayPattern: nil
            )
        }

        let matches = all.filter { recurrenceKey(for: $0) == key }
        let id = transaction.persistentModelID

        let others = matches
            .filter { $0.persistentModelID != id }
            .sorted { $0.date > $1.date }

        // Most recent occurrence strictly before this row.
        let lastOccurrence = others
            .filter { $0.date < transaction.date }
            .map(\.date)
            .max()

        // Averages over same-currency rows only.
        let sameCurrency = matches.filter { $0.currencyCode == transaction.currencyCode }
        let averageAmount = mean(of: sameCurrency.map(\.amount))

        // "This vs the rest" — average the *other* same-currency rows so a
        // single occurrence never compares against itself.
        let otherAmounts = sameCurrency
            .filter { $0.persistentModelID != id }
            .map(\.amount)
        let amountDeltaFraction = deltaFraction(of: transaction.amount, vs: mean(of: otherAmounts))

        return TransactionInsights(
            occurrenceCount: matches.count,
            similar: Array(others.prefix(5)),
            cadence: detectCadence(dates: matches.map(\.date)),
            averageAmount: averageAmount,
            amountDeltaFraction: amountDeltaFraction,
            lastOccurrence: lastOccurrence,
            dayPattern: detectDayPattern(dates: matches.map(\.date), calendar: calendar)
        )
    }

    /// The grouping key two transactions must share to count as "the same
    /// recurring thing": the same kind, plus either a normalized title or
    /// (when there's no title) the category name. `nil` for rows that don't
    /// belong to any group — transfers, manual balance edits, and untitled
    /// uncategorized rows.
    static func recurrenceKey(for tx: Transaction) -> String? {
        guard !tx.isTransfer, !tx.isManualBalanceEdit else { return nil }

        let normalizedTitle = tx.title
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        let kindTag = tx.kind.rawValue
        if !normalizedTitle.isEmpty {
            return "\(kindTag)|t:\(normalizedTitle)"
        }
        if let category = tx.category {
            return "\(kindTag)|c:\(category.name)"
        }
        return nil
    }

    // MARK: Cadence

    /// Infer a recurrence from the gaps between occurrences. Needs at least
    /// three occurrences (two gaps) to say anything. A low spread of gaps
    /// near a known period maps to a named cadence; otherwise it's reported
    /// as `.irregular` with the average gap.
    static func detectCadence(dates: [Date]) -> Cadence? {
        guard dates.count >= 3 else { return nil }

        let sorted = dates.sorted()
        let gaps: [Double] = zip(sorted.dropFirst(), sorted).map {
            $0.timeIntervalSince($1) / 86_400   // seconds → days
        }
        guard !gaps.isEmpty else { return nil }

        let mean = gaps.reduce(0, +) / Double(gaps.count)
        guard mean > 0 else { return nil }

        // Coefficient of variation: how consistent the gaps are relative to
        // their size. A monthly bill that lands 28–33 days apart is tight;
        // a "sometimes weekly, sometimes monthly" spend is not.
        let variance = gaps.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(gaps.count)
        let coefficientOfVariation = variance.squareRoot() / mean

        if coefficientOfVariation <= 0.4, let named = namedCadence(forMeanDays: mean) {
            return named
        }
        return .irregular(averageDays: Int(mean.rounded()))
    }

    /// Map an average gap (in days) onto the nearest familiar period, with a
    /// tolerance window around each so real-world jitter still classifies.
    private static func namedCadence(forMeanDays mean: Double) -> Cadence? {
        switch mean {
        case 5...10:    return .weekly
        case 11...18:   return .biweekly
        case 24...38:   return .monthly
        case 80...100:  return .quarterly
        case 330...400: return .yearly
        default:        return nil
        }
    }

    // MARK: Day pattern

    /// Look for a dominant timing tendency. Weekend (Fri/Sat) wins if a clear
    /// majority of occurrences land there; otherwise the month is split into
    /// thirds and the leading third wins only on a clear majority.
    static func detectDayPattern(dates: [Date], calendar: Calendar) -> DayPattern? {
        guard dates.count >= 3 else { return nil }
        let total = Double(dates.count)
        let majority = 0.6

        // Gregorian weekday: 1 = Sunday … 6 = Friday, 7 = Saturday.
        let weekendCount = dates.filter {
            let weekday = calendar.component(.weekday, from: $0)
            return weekday == 6 || weekday == 7
        }.count
        if Double(weekendCount) / total >= majority { return .weekend }

        var start = 0, mid = 0, end = 0
        for date in dates {
            switch calendar.component(.day, from: date) {
            case ...10:   start += 1
            case 11...20: mid += 1
            default:      end += 1
            }
        }
        let ranked: [(DayPattern, Int)] = [(.startOfMonth, start), (.midMonth, mid), (.endOfMonth, end)]
        guard let (pattern, count) = ranked.max(by: { $0.1 < $1.1 }),
              Double(count) / total >= majority
        else { return nil }
        return pattern
    }

    // MARK: Small numeric helpers

    /// Arithmetic mean of a `Decimal` list, or `nil` when empty.
    private static func mean(of values: [Decimal]) -> Decimal? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Decimal(values.count)
    }

    /// Signed fraction of `value` away from `baseline`, or `nil` when there's
    /// no usable baseline (missing or zero).
    private static func deltaFraction(of value: Decimal, vs baseline: Decimal?) -> Double? {
        guard let baseline, baseline > 0 else { return nil }
        let delta = (value - baseline) / baseline
        return (delta as NSDecimalNumber).doubleValue
    }
}
