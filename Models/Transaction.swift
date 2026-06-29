import Foundation
import SwiftData

/// A single income or expense entry — the log the user adds to over time.
///
/// Kept separate from `Account.balance`: transactions feed the dashboard and
/// budget calculations, but they don't change account balances automatically.
@Model
final class Transaction {
    var amount: Decimal = 0
    var kind: TransactionKind = TransactionKind.expense
    var date: Date = Date.now
    /// Short headline the user types in the "new transaction" sheet
    /// (e.g. "סופר", "מתנה לאמא"). The list view uses it as the row
    /// title; falls back to the category name when empty.
    var title: String = ""
    /// Longer free-text "extra details" field — the row keeps it as a
    /// caption underneath the title when present.
    var note: String = ""
    /// Currency of this entry (multi-currency support).
    var currencyCode: String = "ILS"

    /// Snapshot of the linked account's balance *immediately after* this
    /// transaction was applied, in the account's own currency. Lets the
    /// transactions list show the running balance the user actually saw
    /// when they entered the row, without recomputing it across the
    /// history (which would drift if older rows are edited later).
    /// Optional so legacy rows from before this field existed stay
    /// readable and CloudKit migration stays clean.
    var balanceAfter: Decimal?

    // To-one links are optional, which is also what CloudKit requires.
    var category: Category?
    var account: Account?

    /// Files the user attached to this row — photographed receipts, PDF
    /// invoices, screenshots. Cascade: an attachment has no meaning without
    /// its transaction, so deleting the row deletes its blobs too (no
    /// orphaned external-storage files left behind).
    @Relationship(deleteRule: .cascade, inverse: \TransactionAttachment.transaction)
    var attachments: [TransactionAttachment] = []

    // MARK: - Transfer support
    //
    // A transfer between two accounts is modelled as a *single* row rather
    // than as a new `TransactionKind` case: `TransactionKind` is shared by
    // `Category` and `BudgetItem`, where "transfer" is meaningless, and a
    // third case would force every exhaustive switch across budget /
    // analytics to grow a dead branch. Instead a transfer reuses the
    // income/expense machinery and is identified by `isTransfer` — the
    // same marker philosophy as `isManualBalanceEdit`.
    //
    // For a transfer: `account` is the *source* (money leaves it),
    // `amount` / `currencyCode` describe what left the source, and the two
    // fields below describe what landed in the destination. `kind` is left
    // at its default and ignored — `isTransfer` gates all special handling.

    /// The account a transfer credits. `nil` for ordinary income/expense.
    /// Inverse declared on `Account.incomingTransfers`.
    var destinationAccount: Account?

    /// Amount credited to `destinationAccount`, in *that account's* own
    /// currency. Equals `amount` for a same-currency transfer; for a
    /// cross-currency transfer it's the converted figure, captured at
    /// creation so the reversal is exact and never re-runs FX. Its
    /// presence (non-nil) is the canonical "this row is a transfer"
    /// signal — it survives an account being deleted (which would nil out
    /// `destinationAccount`), so totals stay correct even then.
    var destinationAmount: Decimal?

    /// Snapshot of `destinationAccount`'s balance *immediately after* this
    /// transfer credited it, in that account's own currency — the transfer
    /// counterpart to `balanceAfter` (which snapshots the *source*). Lets
    /// the transactions list show the running balance on *both* sides of a
    /// transfer. `nil` for ordinary income/expense rows and for transfers
    /// written before this field existed (which then show only the source
    /// balance, exactly as before).
    var destinationBalanceAfter: Decimal?

    /// When this row was soft-deleted, or `nil` while it's live. Deleting
    /// a transaction reverses its balance effect and hides the row (every
    /// transaction `@Query` filters `deletedAt == nil`) so it can be
    /// restored from "Recently Deleted", which re-applies the effect.
    /// `TrashService.purgeExpired` hard-deletes rows past the retention
    /// window. Optional + default `nil` keeps the change additive and
    /// CloudKit-compatible.
    var deletedAt: Date?

    init(
        amount: Decimal = 0,
        kind: TransactionKind = .expense,
        date: Date = .now,
        title: String = "",
        note: String = "",
        currencyCode: String = "ILS",
        balanceAfter: Decimal? = nil,
        category: Category? = nil,
        account: Account? = nil,
        destinationAccount: Account? = nil,
        destinationAmount: Decimal? = nil,
        destinationBalanceAfter: Decimal? = nil
    ) {
        self.amount = amount
        self.kind = kind
        self.date = date
        self.title = title
        self.note = note
        self.currencyCode = currencyCode
        self.balanceAfter = balanceAfter
        self.category = category
        self.account = account
        self.destinationAccount = destinationAccount
        self.destinationAmount = destinationAmount
        self.destinationBalanceAfter = destinationBalanceAfter
    }

    /// True when this row moves money between two accounts rather than
    /// logging income or expense. Keyed off `destinationAmount` (not the
    /// relationship) so it stays reliable even if an involved account is
    /// later deleted and its link nullified.
    var isTransfer: Bool { destinationAmount != nil }

    /// Whether this row carries any attached files. Lets the list show a
    /// small paperclip affordance without materializing the blobs.
    var hasAttachments: Bool { !attachments.isEmpty }

    // MARK: - Manual balance-edit marker

    /// Title used for the bookkeeping row that gets inserted whenever
    /// the user manually adjusts an account's cash balance. Centralised
    /// here so the creator (`AccountDraft.apply(to:in:)`) and consumers
    /// that want to exclude these rows (e.g. `BudgetVsActualCard`)
    /// agree on a single literal. Not added as a stored Bool field
    /// because doing so would touch the SwiftData schema; a marker
    /// title is enough and keeps CloudKit-compatibility cleaner.
    static let manualBalanceEditTitle = "עריכה ידנית"

    /// True when this row was inserted by the manual-balance-edit
    /// path rather than by the user adding a real income/expense.
    /// The extra `category == nil` check makes it harder for a normal
    /// transaction the user happens to title "עריכה ידנית" to be
    /// silently excluded from monthly totals.
    var isManualBalanceEdit: Bool {
        title == Transaction.manualBalanceEditTitle && category == nil
    }
}

// MARK: - Balance effect

extension Transaction {
    /// The signed effect this transaction had on its linked account's
    /// balance, expressed in the *account's own* currency: income is
    /// positive, expense negative. This mirrors the math the "new
    /// transaction" sheet runs when the row is created, so the editor
    /// (swap old effect for new) and the list's delete action (reverse
    /// the effect) can keep the manually-tracked balance honest.
    ///
    /// Returns `nil` when there's no linked account, or when the entry's
    /// currency differs from the account's and no FX snapshot can bridge
    /// them. Same-currency entries — the overwhelmingly common case in a
    /// single-user ILS ledger — need no FX and are always exact;
    /// cross-currency entries reuse the latest cached rate, which can
    /// differ slightly from the rate used at creation. That's the same
    /// drift the app already tolerates for its `balanceAfter` snapshots.
    func balanceEffect(using snapshot: FXRateSnapshot?) -> Decimal? {
        guard let account else { return nil }

        let inAccountCurrency: Decimal
        if currencyCode == account.currencyCode {
            inAccountCurrency = amount
        } else if let snapshot,
                  let converted = CurrencyConverter.convert(
                    amount,
                    from: currencyCode,
                    to: account.currencyCode,
                    using: snapshot
                  ) {
            inAccountCurrency = converted
        } else {
            return nil
        }

        switch kind {
        case .income:  return inAccountCurrency
        case .expense: return -inAccountCurrency
        }
    }

    /// Undo this transaction's effect on its account balance(s), used by
    /// the list's delete action. Transfer-aware: a transfer debited the
    /// source and credited the destination, so both are unwound using the
    /// amounts captured at creation (`amount` for the source, the stored
    /// `destinationAmount` for the destination) — no FX needed. Ordinary
    /// rows reverse their single `balanceEffect`; if that can't be
    /// computed (cross-currency with no snapshot) the balance is left
    /// untouched, matching the previous inline behaviour.
    func reverseEffect(using snapshot: FXRateSnapshot?) {
        if isTransfer {
            if let source = account {
                source.balance += amount
                source.lastUpdated = .now
            }
            if let destination = destinationAccount {
                destination.balance -= destinationAmount ?? amount
                destination.lastUpdated = .now
            }
        } else if let account, let effect = balanceEffect(using: snapshot) {
            account.balance -= effect
            account.lastUpdated = .now
        }
    }

    /// Re-apply this transaction's effect on its account balance(s) — the
    /// exact inverse of `reverseEffect`, used when a soft-deleted row is
    /// restored from "Recently Deleted". A delete reversed the effect (the
    /// money came back); restoring puts it back. Transfer-aware and FX-free
    /// for the same reasons as `reverseEffect`: the transfer figures were
    /// captured at creation, and a cross-currency ordinary row that can't be
    /// expressed in the account's currency is left untouched.
    func reapplyEffect(using snapshot: FXRateSnapshot?) {
        if isTransfer {
            if let source = account {
                source.balance -= amount
                source.lastUpdated = .now
            }
            if let destination = destinationAccount {
                destination.balance += destinationAmount ?? amount
                destination.lastUpdated = .now
            }
        } else if let account, let effect = balanceEffect(using: snapshot) {
            account.balance += effect
            account.lastUpdated = .now
        }
    }
}
