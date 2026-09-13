import Foundation

/// The fixed-term side of a savings account — "₪50,000 at 4.2% until 1 Jan 2027".
///
/// A pure value type with no SwiftData or SwiftUI in it, so the term maths can
/// be unit-tested on its own (and lives in the test target alongside the app
/// target). `Account` stores the raw fields; this type answers the questions
/// the UI actually asks: has it matured, how far through the term are we, and
/// what is it worth.
///
/// **Interest model: simple annual interest, pro-rated by elapsed days.**
/// `value = principal × (1 + rate × years)`. Not compounding — most of the
/// deposits this app is for are short, the difference over a year or two is
/// small, and a figure the user can reproduce on a calculator is worth more
/// here than one that's theoretically closer to the bank's. The payout prompt
/// pre-fills this number but lets the user type the bank's actual figure over
/// it, which is the real source of truth.
struct DepositTerms: Equatable {

    /// The amount deposited at the start of the term, in the account's own
    /// currency.
    let principal: Decimal

    /// Annual nominal rate as a percentage — `4.2` means 4.2% a year. `nil`
    /// for a savings account the user never attached a rate to, which then
    /// simply holds its principal.
    let annualRatePercent: Decimal?

    let startDate: Date

    /// The day the deposit pays out. `nil` for an open-ended savings pot: it
    /// never matures, so it never raises the payout prompt.
    let maturityDate: Date?

    /// Day count convention. 365 flat (not 365.25, not 360): it matches how
    /// the user would work the number out by hand.
    private static let daysPerYear = 365

    init(
        principal: Decimal,
        annualRatePercent: Decimal? = nil,
        startDate: Date,
        maturityDate: Date? = nil
    ) {
        self.principal = principal
        self.annualRatePercent = annualRatePercent
        self.startDate = startDate
        self.maturityDate = maturityDate
    }

    // MARK: - Term state

    /// True once the maturity day has arrived (or passed). Compared at
    /// day granularity, not by instant: a deposit maturing "1 January" is
    /// due the moment that day starts, not at 00:00 plus whatever time of
    /// day the user happened to pick in the date picker.
    func isMatured(asOf now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let maturityDate else { return false }
        return calendar.startOfDay(for: now) >= calendar.startOfDay(for: maturityDate)
    }

    /// Whole days left until maturity — 0 on the maturity day itself and
    /// negative once it's passed. `nil` without a maturity date.
    func daysRemaining(asOf now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let maturityDate else { return nil }
        return Self.days(from: now, to: maturityDate, calendar: calendar)
    }

    /// How far through the term we are, clamped to 0…1, for a progress bar.
    /// `nil` when there's no maturity date (nothing to be a fraction of) or
    /// when the term has no length at all.
    func progress(asOf now: Date = .now, calendar: Calendar = .current) -> Double? {
        guard let maturityDate else { return nil }
        let total = Self.days(from: startDate, to: maturityDate, calendar: calendar)
        guard total > 0 else { return isMatured(asOf: now, calendar: calendar) ? 1 : 0 }
        let elapsed = Self.days(from: startDate, to: now, calendar: calendar)
        return min(max(Double(elapsed) / Double(total), 0), 1)
    }

    // MARK: - Value

    /// What the deposit is worth on a given date: principal plus the interest
    /// accrued from `startDate` up to that date. Accrual stops at maturity —
    /// a deposit the user hasn't got round to withdrawing doesn't keep earning
    /// on these terms — and never runs backwards before the start date.
    func value(asOf date: Date, calendar: Calendar = .current) -> Decimal {
        guard let annualRatePercent, annualRatePercent != 0 else { return principal }

        // Cap the accrual window at maturity, so a payout confirmed three
        // weeks late is still worth exactly what the term promised.
        var end = date
        if let maturityDate, end > maturityDate { end = maturityDate }

        let days = Self.days(from: startDate, to: end, calendar: calendar)
        guard days > 0 else { return principal }

        let years = Decimal(days) / Decimal(Self.daysPerYear)
        let interest = principal * (annualRatePercent / 100) * years
        return Self.roundedToCents(principal + interest)
    }

    /// What the deposit pays out at the end of its term — the figure the
    /// maturity prompt pre-fills. Falls back to the principal when the
    /// deposit has no maturity date to run to.
    var projectedValue: Decimal {
        guard let maturityDate else { return principal }
        return value(asOf: maturityDate)
    }

    /// Interest earned over the full term (0 when no rate was set).
    var projectedInterest: Decimal { projectedValue - principal }

    // MARK: - Helpers

    /// Whole calendar days between two dates, normalised to day boundaries so
    /// clock time (and DST) can't shift the count by one.
    private static func days(from: Date, to: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// Money is `Decimal` throughout the app, and a rate times a day fraction
    /// produces far more places than a currency has. Round once, here, so
    /// every caller sees the same figure.
    private static func roundedToCents(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }
}
