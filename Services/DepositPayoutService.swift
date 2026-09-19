import Foundation
import SwiftData

/// Moves a matured deposit's money into the account it pays out to.
///
/// Kept out of the views because two different callers need it: the dashboard
/// prompt the user confirms by hand, and the automatic payout that runs on
/// launch for deposits set to `autoPayoutOnMaturity`.
///
/// **The payout is an ordinary transfer row.** Rather than invent a new kind
/// of movement, it reuses `Transaction`'s transfer shape (`destinationAmount`
/// plus both `balanceAfter` snapshots), so the money shows up in the ledger,
/// reverses correctly if the user deletes it, and is restorable from Recently
/// Deleted — all without a line of new balance code.
enum DepositPayoutService {

    /// Live deposits that have reached maturity and still hold their money.
    /// Ordered oldest-maturity first so a backlog is cleared in the order it
    /// came due.
    static func depositsAwaitingPayout(in accounts: [Account], asOf now: Date = .now) -> [Account] {
        accounts
            .filter { $0.isAwaitingPayout(asOf: now) }
            // By the day the money is actually due, which for a replenishable
            // deposit is its *last* sub-deposit's — not the account's own.
            .sorted {
                ($0.effectiveMaturityDate ?? .distantFuture) < ($1.effectiveMaturityDate ?? .distantFuture)
            }
    }

    /// What the prompt pre-fills, and what an automatic payout moves: the
    /// deposit's projected value at maturity (principal + interest for the
    /// term). Falls back to the plain balance for a deposit with no rate.
    ///
    /// The user can type over this in the prompt — the bank's actual figure
    /// wins over our arithmetic whenever the two disagree.
    /// Reads the *ladder*, so a replenishable deposit pays out the sum of its
    /// sub-deposits — each grown on its own rate for its own term — rather than
    /// the whole balance run on the account's headline terms.
    static func suggestedPayoutAmount(for deposit: Account) -> Decimal {
        deposit.depositLadder?.projectedValue ?? deposit.balance
    }

    /// Whether the money can actually be moved into `target` right now. False
    /// only when the two accounts are in different currencies and there's no
    /// FX snapshot to bridge them — we refuse to invent a rate for a figure
    /// that lands in a real balance.
    static func canPayOut(_ deposit: Account, to target: Account, using snapshot: FXRateSnapshot?) -> Bool {
        convertedAmount(1, from: deposit, to: target, using: snapshot) != nil
    }

    /// Pay the deposit out into `target`.
    ///
    /// Two rows are written, in this order:
    ///  1. **Interest** — the gap between what the account currently holds
    ///     (the principal the user entered) and the agreed payout figure,
    ///     logged against the deposit as income. Interest earned is real
    ///     income and belongs in the ledger; without this row the transfer
    ///     would drag the deposit's balance negative by exactly the interest.
    ///     A user who types a figure *below* the balance gets the mirror
    ///     image, an expense row, for the same reason.
    ///  2. **Transfer** — deposit → target for the full amount.
    ///
    /// Returns the transfer, or `nil` (having changed nothing) when the
    /// currencies can't be bridged.
    @discardableResult
    static func payOut(
        _ deposit: Account,
        amount: Decimal,
        to target: Account,
        in context: ModelContext,
        using snapshot: FXRateSnapshot?,
        on date: Date = .now
    ) -> Transaction? {
        guard let creditedAmount = convertedAmount(amount, from: deposit, to: target, using: snapshot) else {
            return nil
        }

        // 1. Bring the deposit's balance up (or down) to the agreed figure.
        let interest = amount - deposit.balance
        if interest != 0 {
            let kind: TransactionKind = interest > 0 ? .income : .expense
            deposit.balance += interest
            let interestRow = Transaction(
                amount: abs(interest),
                kind: kind,
                date: date,
                title: Transaction.depositInterestTitle,
                currencyCode: deposit.currencyCode,
                balanceAfter: deposit.balance,
                account: deposit
            )
            context.insert(interestRow)
        }

        // 2. Move the whole balance across. Mirrors `NewTransactionSheet`'s
        //    `insertTransfer`: debit the source by what left it, credit the
        //    destination by the converted figure, and snapshot both running
        //    balances on the row.
        deposit.balance -= amount
        target.balance += creditedAmount
        deposit.lastUpdated = date
        target.lastUpdated = date

        let transfer = Transaction(
            amount: amount,
            date: date,
            title: payoutTitle(for: deposit),
            currencyCode: deposit.currencyCode,
            balanceAfter: deposit.balance,
            account: deposit,
            destinationAccount: target,
            destinationAmount: creditedAmount,
            destinationBalanceAfter: target.balance
        )
        context.insert(transfer)

        // Latch it closed so the maturity prompt never comes back for this
        // deposit. The account itself stays — at zero, with its terms intact —
        // so the user can see what it was and delete it when they're ready.
        deposit.payoutCompletedAt = date

        return transfer
    }

    // MARK: - Helpers

    static func payoutTitle(for deposit: Account) -> String {
        let name = deposit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "פדיון פיקדון" : "פדיון פיקדון — \(name)"
    }

    /// `amount` expressed in the target account's own currency.
    private static func convertedAmount(
        _ amount: Decimal,
        from deposit: Account,
        to target: Account,
        using snapshot: FXRateSnapshot?
    ) -> Decimal? {
        guard deposit.currencyCode != target.currencyCode else { return amount }
        guard let snapshot else { return nil }
        return CurrencyConverter.convert(
            amount,
            from: deposit.currencyCode,
            to: target.currencyCode,
            using: snapshot
        )
    }
}
