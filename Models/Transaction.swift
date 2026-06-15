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

    init(
        amount: Decimal = 0,
        kind: TransactionKind = .expense,
        date: Date = .now,
        title: String = "",
        note: String = "",
        currencyCode: String = "ILS",
        balanceAfter: Decimal? = nil,
        category: Category? = nil,
        account: Account? = nil
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
    }

    // MARK: - Manual balance-edit marker

    /// Title used for the bookkeeping row that gets inserted whenever
    /// the user manually adjusts an account's cash balance. Centralised
    /// here so the creator (`AccountDraft.apply(to:in:)`) and consumers
    /// that want to exclude these rows (e.g. `MonthlySummaryCard`)
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
