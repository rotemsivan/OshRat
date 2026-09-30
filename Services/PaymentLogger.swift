import Foundation
import SwiftData

/// Logs a waiting card payment straight to the ledger, without its sheet —
/// the "רישום כולם" button in `NewTransactionSheet` when several payments
/// are waiting.
///
/// A payment is written only when it is **complete**: everything the sheet
/// would insist on before it lets the user save (`canConfirm`) is there —
/// an amount, a title, a category and an account the amount can be booked
/// in. The title, category and account come from `PaymentPrefill.resolve`,
/// i.e. from how the user logged earlier payments at the same shop, so a
/// regular's coffee is complete and a first visit usually lacks a category.
/// An incomplete payment goes back in the queue for its own sheet.
///
/// The row is written the way the sheet writes a new expense: the amount and
/// currency as paid, the account's balance moved by the amount in the
/// account's currency, `balanceAfter` snapshotting it, and the payment's raw
/// merchant and card kept for next time.
@MainActor
enum PaymentLogger {

    /// The amount in the account's own currency, or `nil` when there's no
    /// rate to get it there (the sheet blocks saving in that case too).
    static func accountAmount(
        for payment: PaymentPrefill,
        in account: Account,
        fxSnapshot: FXRateSnapshot?
    ) -> Decimal? {
        guard let amount = payment.amount, amount > 0 else { return nil }
        let code = payment.currencyCode ?? account.currencyCode
        if code == account.currencyCode { return amount }
        guard let fxSnapshot else { return nil }
        return CurrencyConverter.convert(amount, from: code, to: account.currencyCode, using: fxSnapshot)
    }

    static func isComplete(
        _ payment: PaymentPrefill,
        _ resolved: PaymentPrefill.Resolved,
        fxSnapshot: FXRateSnapshot?
    ) -> Bool {
        guard let account = resolved.account, resolved.category != nil,
              !resolved.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        return accountAmount(for: payment, in: account, fxSnapshot: fxSnapshot) != nil
    }

    /// Inserts the payment as an expense, or does nothing and returns `nil`
    /// when it isn't complete. The caller saves.
    @discardableResult
    static func log(
        _ payment: PaymentPrefill,
        _ resolved: PaymentPrefill.Resolved,
        fxSnapshot: FXRateSnapshot?,
        in context: ModelContext,
        now: Date = .now
    ) -> Transaction? {
        guard isComplete(payment, resolved, fxSnapshot: fxSnapshot),
              let account = resolved.account,
              let amount = payment.amount,
              let accountAmount = accountAmount(for: payment, in: account, fxSnapshot: fxSnapshot)
        else { return nil }

        account.balance -= accountAmount
        account.lastUpdated = now

        let transaction = Transaction(
            amount: amount,
            kind: .expense,
            // When the card was tapped, not when the button was — a payment
            // may have waited hours for this.
            date: min(payment.receivedAt, now),
            title: resolved.title.trimmingCharacters(in: .whitespacesAndNewlines),
            currencyCode: payment.currencyCode ?? account.currencyCode,
            balanceAfter: account.balance,
            category: resolved.category,
            account: account
        )
        transaction.paymentMerchant = payment.trimmedMerchant
        transaction.paymentCardName = payment.trimmedCardName
        context.insert(transaction)
        return transaction
    }
}
