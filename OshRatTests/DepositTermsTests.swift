import Testing
import Foundation
@testable import OshRat

/// Term maths for a savings deposit. `DepositTerms` is a pure value type, so
/// everything here is exercised with fixed dates and a fixed calendar rather
/// than against the store.
struct DepositTermsTests {

    /// Gregorian calendar pinned to UTC so the day-count assertions don't
    /// shift with whatever timezone the test machine runs in.
    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Maturity

    @Test func openEndedSavingsNeverMatures() {
        let terms = DepositTerms(
            principal: 10_000,
            annualRatePercent: 3,
            startDate: Self.date(2026, 1, 1),
            maturityDate: nil
        )
        #expect(terms.isMatured(asOf: Self.date(2099, 1, 1), calendar: Self.calendar) == false)
        #expect(terms.daysRemaining(asOf: Self.date(2026, 6, 1), calendar: Self.calendar) == nil)
        #expect(terms.progress(asOf: Self.date(2026, 6, 1), calendar: Self.calendar) == nil)
    }

    @Test func maturesOnTheMaturityDayItself() {
        let terms = DepositTerms(
            principal: 10_000,
            annualRatePercent: 3,
            startDate: Self.date(2026, 1, 1),
            maturityDate: Self.date(2027, 1, 1)
        )
        #expect(terms.isMatured(asOf: Self.date(2026, 12, 31), calendar: Self.calendar) == false)
        // The maturity day counts as matured from the moment it starts, not
        // from the time-of-day the picker happened to store.
        #expect(terms.isMatured(asOf: Self.date(2027, 1, 1), calendar: Self.calendar))
        #expect(terms.isMatured(asOf: Self.date(2027, 3, 1), calendar: Self.calendar))
    }

    @Test func daysRemainingGoesNegativeOnceOverdue() {
        let terms = DepositTerms(
            principal: 1_000,
            startDate: Self.date(2026, 1, 1),
            maturityDate: Self.date(2026, 1, 31)
        )
        #expect(terms.daysRemaining(asOf: Self.date(2026, 1, 1), calendar: Self.calendar) == 30)
        #expect(terms.daysRemaining(asOf: Self.date(2026, 1, 31), calendar: Self.calendar) == 0)
        #expect(terms.daysRemaining(asOf: Self.date(2026, 2, 5), calendar: Self.calendar) == -5)
    }

    // MARK: - Value

    @Test func noRateMeansTheDepositIsWorthItsPrincipal() {
        let terms = DepositTerms(
            principal: 25_000,
            annualRatePercent: nil,
            startDate: Self.date(2026, 1, 1),
            maturityDate: Self.date(2028, 1, 1)
        )
        #expect(terms.projectedValue == 25_000)
        #expect(terms.projectedInterest == 0)
    }

    @Test func fullYearAtFivePercentEarnsFivePercent() {
        let terms = DepositTerms(
            principal: 10_000,
            annualRatePercent: 5,
            startDate: Self.date(2026, 1, 1),
            maturityDate: Self.date(2027, 1, 1)
        )
        // 365 days / 365 = exactly one year of simple interest.
        #expect(terms.projectedValue == 10_500)
        #expect(terms.projectedInterest == 500)
    }

    @Test func interestIsProRatedByElapsedDays() {
        let terms = DepositTerms(
            principal: 10_000,
            annualRatePercent: 5,
            startDate: Self.date(2026, 1, 1),
            maturityDate: Self.date(2027, 1, 1)
        )
        // 73 days in = a fifth of the 365-day year, so a fifth of the 500.
        let partway = terms.value(asOf: Self.date(2026, 3, 15), calendar: Self.calendar)
        #expect(partway == 10_100)
    }

    @Test func simpleInterestDoesNotCompoundAcrossYears() {
        let terms = DepositTerms(
            principal: 10_000,
            annualRatePercent: 5,
            startDate: Self.date(2026, 1, 1),
            maturityDate: Self.date(2028, 1, 1)
        )
        // 730 days = two years: 1,000 simple, not the 1,025 compounding gives.
        #expect(terms.projectedValue == 11_000)
    }

    @Test func accrualStopsAtMaturity() {
        let terms = DepositTerms(
            principal: 10_000,
            annualRatePercent: 5,
            startDate: Self.date(2026, 1, 1),
            maturityDate: Self.date(2027, 1, 1)
        )
        // Confirming the payout three months late must not pay three months
        // of extra interest — the term ended.
        let late = terms.value(asOf: Self.date(2027, 4, 1), calendar: Self.calendar)
        #expect(late == terms.projectedValue)
    }

    @Test func valueBeforeTheStartDateIsJustThePrincipal() {
        let terms = DepositTerms(
            principal: 10_000,
            annualRatePercent: 5,
            startDate: Self.date(2026, 6, 1),
            maturityDate: Self.date(2027, 6, 1)
        )
        #expect(terms.value(asOf: Self.date(2026, 1, 1), calendar: Self.calendar) == 10_000)
    }

    @Test func valueIsRoundedToCents() {
        let terms = DepositTerms(
            principal: 3_333,
            annualRatePercent: 3.7,
            startDate: Self.date(2026, 1, 1),
            maturityDate: Self.date(2026, 4, 17)
        )
        // Whatever the fraction works out to, it must be a currency figure —
        // two places, no long decimal tail.
        let value = terms.projectedValue
        let cents = value * 100
        #expect(cents == (cents as NSDecimalNumber).rounding(accordingToBehavior: nil) as Decimal)
    }

    // MARK: - Progress

    @Test func progressRunsZeroToOneAcrossTheTerm() {
        let terms = DepositTerms(
            principal: 1_000,
            startDate: Self.date(2026, 1, 1),
            maturityDate: Self.date(2026, 1, 11)
        )
        #expect(terms.progress(asOf: Self.date(2026, 1, 1), calendar: Self.calendar) == 0)
        #expect(terms.progress(asOf: Self.date(2026, 1, 6), calendar: Self.calendar) == 0.5)
        #expect(terms.progress(asOf: Self.date(2026, 1, 11), calendar: Self.calendar) == 1)
        // Clamped, so an overdue deposit reads as full rather than past full.
        #expect(terms.progress(asOf: Self.date(2026, 2, 1), calendar: Self.calendar) == 1)
        #expect(terms.progress(asOf: Self.date(2025, 12, 1), calendar: Self.calendar) == 0)
    }
}
