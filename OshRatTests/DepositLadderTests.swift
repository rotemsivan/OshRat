import Testing
import Foundation
@testable import OshRat

/// The ladder maths behind a replenishable deposit — one where every transfer
/// in becomes a sub-deposit with its own term. `DepositLadder` is pure, so
/// everything here runs on fixed dates and a fixed calendar, exactly like
/// `DepositTermsTests`.
struct DepositLadderTests {

    /// Gregorian calendar pinned to UTC so day counts don't move with the test
    /// machine's timezone.
    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// The account's own terms. `principal` is always ignored by `make` — the
    /// opening deposit is whatever the additions don't account for.
    private static func opening(
        rate: Decimal? = 4,
        start: Date = DepositLadderTests.date(2026, 1, 1),
        maturity: Date? = DepositLadderTests.date(2027, 1, 1)
    ) -> DepositTerms {
        DepositTerms(principal: 0, annualRatePercent: rate, startDate: start, maturityDate: maturity)
    }

    // MARK: - Shape

    @Test func oneTimeDepositIsASingleRungLadder() {
        let ladder = DepositLadder.make(balance: 10_000, opening: Self.opening(), additions: [])

        #expect(ladder.tranches.count == 1)
        #expect(ladder.principal == 10_000)
        #expect(ladder.maturityDate == Self.date(2027, 1, 1))
        // Same figure `DepositTerms` alone would give: 10,000 at 4% for 365 days.
        #expect(ladder.projectedValue == 10_400)
    }

    @Test func openingRungIsTheBalanceTheAdditionsDoNotExplain() {
        let addition = DepositTerms(
            principal: 3_000,
            annualRatePercent: 4,
            startDate: Self.date(2026, 4, 1),
            maturityDate: Self.date(2027, 4, 1)
        )
        let ladder = DepositLadder.make(balance: 10_000, opening: Self.opening(), additions: [addition])

        #expect(ladder.tranches.count == 2)
        #expect(ladder.principal == 10_000)
        // Oldest first, and the opening holds what's left after the additions.
        #expect(ladder.tranches[0].principal == 7_000)
        #expect(ladder.tranches[0].startDate == Self.date(2026, 1, 1))
        #expect(ladder.tranches[1].principal == 3_000)
    }

    @Test func aDepositFundedEntirelyByTransfersHasNoOpeningMoney() {
        let addition = DepositTerms(
            principal: 5_000,
            annualRatePercent: 4,
            startDate: Self.date(2026, 3, 1),
            maturityDate: Self.date(2027, 3, 1)
        )
        let ladder = DepositLadder.make(balance: 5_000, opening: Self.opening(), additions: [addition])

        #expect(ladder.principal == 5_000)
        // The opening rung is still there — at zero — so the account's own
        // maturity date keeps counting toward when the deposit comes due.
        #expect(ladder.tranches.first?.principal == 0)
    }

    // MARK: - Maturity: the latest rung wins

    @Test func maturityIsTheLatestOfAllSubDeposits() {
        let additions = [
            DepositTerms(
                principal: 1_000,
                startDate: Self.date(2026, 4, 1),
                maturityDate: Self.date(2027, 4, 1)
            ),
            DepositTerms(
                principal: 1_000,
                startDate: Self.date(2026, 2, 1),
                maturityDate: Self.date(2027, 2, 1)
            )
        ]
        let ladder = DepositLadder.make(balance: 10_000, opening: Self.opening(), additions: additions)

        #expect(ladder.maturityDate == Self.date(2027, 4, 1))
        #expect(ladder.startDate == Self.date(2026, 1, 1))
        // Not due while the last rung is still running, even though the
        // opening one matured back in January.
        #expect(ladder.isMatured(asOf: Self.date(2027, 1, 2), calendar: Self.calendar) == false)
        #expect(ladder.isMatured(asOf: Self.date(2027, 4, 1), calendar: Self.calendar))
    }

    @Test func anOpenEndedRungKeepsTheWholeDepositOpen() {
        let addition = DepositTerms(
            principal: 1_000,
            startDate: Self.date(2026, 6, 1),
            maturityDate: nil
        )
        let ladder = DepositLadder.make(balance: 5_000, opening: Self.opening(), additions: [addition])

        #expect(ladder.maturityDate == nil)
        #expect(ladder.isMatured(asOf: Self.date(2099, 1, 1), calendar: Self.calendar) == false)
        #expect(ladder.daysRemaining(asOf: Self.date(2026, 6, 1), calendar: Self.calendar) == nil)
        #expect(ladder.progress(asOf: Self.date(2026, 6, 1), calendar: Self.calendar) == nil)
    }

    // MARK: - Value

    @Test func eachRungEarnsOnItsOwnTermsWithNoCompounding() {
        // 4% for a full year on 7,000 = 280. 5% for a full year on 3,000 = 150.
        let addition = DepositTerms(
            principal: 3_000,
            annualRatePercent: 5,
            startDate: Self.date(2026, 4, 1),
            maturityDate: Self.date(2027, 4, 1)
        )
        let ladder = DepositLadder.make(balance: 10_000, opening: Self.opening(), additions: [addition])

        #expect(ladder.projectedValue == 10_430)
        #expect(ladder.projectedInterest == 430)
    }

    @Test func aMaturedRungStopsAccruingWhileTheRestKeepsGoing() {
        // The opening rung matures 1 Jan 2027; the addition runs to 1 Apr 2027.
        let addition = DepositTerms(
            principal: 3_000,
            annualRatePercent: 5,
            startDate: Self.date(2026, 4, 1),
            maturityDate: Self.date(2027, 4, 1)
        )
        let ladder = DepositLadder.make(balance: 10_000, opening: Self.opening(), additions: [addition])

        // On the opening rung's own maturity day it has earned its full 280,
        // while the addition has only run 275 of its 365 days.
        let value = ladder.value(asOf: Self.date(2027, 1, 1), calendar: Self.calendar)
        #expect(value > 10_280)
        #expect(value < ladder.projectedValue)

        // Past that date the opening rung is frozen: the whole ladder is worth
        // no more than its projection.
        #expect(ladder.value(asOf: Self.date(2027, 4, 1), calendar: Self.calendar) == ladder.projectedValue)
        #expect(ladder.value(asOf: Self.date(2028, 1, 1), calendar: Self.calendar) == ladder.projectedValue)
    }

    // MARK: - Reconciliation against the balance

    @Test func rungsNeverAddUpToMoreThanTheBalance() {
        // The balance was corrected down to 4,000 by hand (or money left the
        // deposit some way that isn't a rung) while 6,000 of additions are on
        // record. The shortfall comes off the newest end.
        let additions = [
            DepositTerms(
                principal: 3_000,
                startDate: Self.date(2026, 2, 1),
                maturityDate: Self.date(2027, 2, 1)
            ),
            DepositTerms(
                principal: 3_000,
                startDate: Self.date(2026, 5, 1),
                maturityDate: Self.date(2027, 5, 1)
            )
        ]
        let ladder = DepositLadder.make(balance: 4_000, opening: Self.opening(), additions: additions)

        #expect(ladder.principal == 4_000)
        #expect(ladder.tranches.count == 2)
        #expect(ladder.tranches[0].principal == 3_000)   // oldest kept whole
        #expect(ladder.tranches[1].principal == 1_000)   // newest trimmed
    }

    @Test func anEmptyDepositHasNothingToPayOut() {
        let ladder = DepositLadder.make(balance: 0, opening: Self.opening(), additions: [])

        #expect(ladder.principal == 0)
        #expect(ladder.projectedValue == 0)
        #expect(ladder.projectedInterest == 0)
    }
}
