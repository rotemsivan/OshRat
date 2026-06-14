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
        category: Category? = nil,
        account: Account? = nil
    ) {
        self.amount = amount
        self.kind = kind
        self.date = date
        self.title = title
        self.note = note
        self.currencyCode = currencyCode
        self.category = category
        self.account = account
    }
}
