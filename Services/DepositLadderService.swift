import Foundation
import SwiftData

/// Keeps a **replenishable** deposit's ladder in step with the ledger.
///
/// The rule the whole feature rests on: *every transfer into a replenishable
/// deposit is a sub-deposit of its own*. Rather than make the user declare one
/// by hand in a second place — and then keep the two in sync — the rung is
/// written from the transfer itself, on terms copied from the account.
///
/// Kept out of the views because the transfer sheet isn't the only thing that
/// will ever credit a deposit, and out of `DepositPayoutService` because that
/// one is about money *leaving*.
///
/// A `@MainActor enum` with no state of its own, like the other services here —
/// the SwiftData store is the state.
@MainActor
enum DepositLadderService {

    /// Record `transfer` as a sub-deposit, if it is one.
    ///
    /// Does nothing (and returns `nil`) unless the transfer credits a live,
    /// not-yet-paid-out replenishable deposit with a positive amount — which
    /// covers ordinary transfers, one-time deposits, and the payout transfer
    /// that empties a deposit at the end of its term.
    ///
    /// The new rung copies the account's rate and term length rather than
    /// pointing at them: terms agreed in March shouldn't change because the
    /// user edited the deposit's defaults in June. The caller saves.
    @discardableResult
    static func registerFunding(for transfer: Transaction, in context: ModelContext) -> DepositTranche? {
        guard let deposit = transfer.destinationAccount,
              deposit.isReplenishable,
              deposit.deletedAt == nil,
              deposit.payoutCompletedAt == nil
        else { return nil }

        // What actually landed, in the deposit's own currency — the transfer
        // already did any FX conversion, and a rung is always denominated in
        // the account it sits in.
        let amount = transfer.destinationAmount ?? transfer.amount
        guard amount > 0 else { return nil }

        let tranche = DepositTranche(
            amount: amount,
            interestRatePercent: deposit.interestRatePercent,
            startDate: transfer.date,
            maturityDate: deposit.defaultTrancheMaturityDate(fundedOn: transfer.date),
            note: transfer.title.trimmingCharacters(in: .whitespacesAndNewlines),
            account: deposit,
            fundingTransaction: transfer
        )
        context.insert(tranche)
        return tranche
    }
}
