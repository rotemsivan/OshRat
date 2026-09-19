import Foundation
import SwiftData

/// One sub-deposit inside a **replenishable** deposit — a single "הפקדה" the
/// user made into a savings account that accepts more money over time.
///
/// Each one is a deposit in its own right: its own principal, its own rate and
/// its own maturity date, all seeded from the account's terms at the moment the
/// money landed. Seeded rather than inherited-by-reference on purpose — a rate
/// the bank agreed in March shouldn't change because the user edited the
/// account's default rate in June.
///
/// **Rungs are created by transfers, not by hand.** `DepositLadderService`
/// writes one whenever a transfer credits a replenishable deposit, which is
/// exactly how money gets into one. The account's *opening* balance has no row
/// here — it's derived as the remainder (see `DepositLadder.make`).
///
/// CloudKit rules apply as everywhere else: every stored property is optional
/// or defaulted, and there are no unique constraints.
@Model
final class DepositTranche {

    /// What went in, in the account's own currency. A rung can't be in a
    /// different currency than the deposit it sits in — the transfer that
    /// created it already converted.
    var amount: Decimal = 0

    /// Annual nominal rate for *this* rung. `nil` falls back to the account's
    /// rate, which is only the case for a rung written before a rate was set.
    var interestRatePercent: Decimal?

    /// When this money started earning — the transfer's date.
    var startDate: Date = Date.now

    /// When this rung comes due. `nil` falls back to the account's own maturity
    /// date. The deposit as a whole pays out on the latest of all of them.
    var maturityDate: Date?

    /// When the row was written, as distinct from `startDate` (which is the
    /// user-chosen transfer date and can be backdated).
    var createdAt: Date = Date.now

    /// Short label, taken from the funding transfer's title, so the deposit's
    /// rungs read as the moves that created them.
    var note: String = ""

    /// The deposit this rung belongs to. Inverse of `Account.depositTranches`,
    /// which cascades — a rung has no meaning without its deposit.
    var account: Account?

    /// The transfer that funded this rung. Inverse of
    /// `Transaction.fundedDepositTranches`, which **cascades**: no transfer, no
    /// sub-deposit. Soft-deleting that transfer doesn't destroy the rung, it
    /// only takes it out of the ladder (see `isLive`), so restoring the row
    /// from Recently Deleted brings the rung back with it.
    ///
    /// `nil` for a rung with no ledger row behind it — nothing writes one today,
    /// but the field stays optional for CloudKit and for a future "record an
    /// existing deposit's history" flow.
    var fundingTransaction: Transaction?

    init(
        amount: Decimal = 0,
        interestRatePercent: Decimal? = nil,
        startDate: Date = .now,
        maturityDate: Date? = nil,
        createdAt: Date = .now,
        note: String = "",
        account: Account? = nil,
        fundingTransaction: Transaction? = nil
    ) {
        self.amount = amount
        self.interestRatePercent = interestRatePercent
        self.startDate = startDate
        self.maturityDate = maturityDate
        self.createdAt = createdAt
        self.note = note
        self.account = account
        self.fundingTransaction = fundingTransaction
    }

    /// Whether this rung counts right now. A rung whose funding transfer sits
    /// in Recently Deleted doesn't: deleting the transfer already took the
    /// money back out of the balance, so counting the rung would ladder money
    /// that isn't there.
    var isLive: Bool {
        fundingTransaction?.deletedAt == nil
    }

    /// This rung as pure term maths, filling in whatever it inherits from the
    /// deposit it sits in.
    func terms(inheritingFrom account: Account?) -> DepositTerms {
        DepositTerms(
            principal: amount,
            annualRatePercent: interestRatePercent ?? account?.interestRatePercent,
            startDate: startDate,
            maturityDate: maturityDate ?? account?.maturityDate
        )
    }
}
