import Foundation
import SwiftData

/// A financial account whose balance the user maintains by hand
/// (current account, savings, investments…).
///
/// The `balance` here is the source of truth for net worth — we do NOT
/// recompute it from transactions. Transactions are a separate log.
@Model
final class Account {
    var name: String = ""
    var type: AccountType = AccountType.current
    /// Money is always `Decimal`, never `Double`, to avoid rounding errors.
    var balance: Decimal = 0
    /// ISO currency code, e.g. "ILS" or "USD" (multi-currency support).
    var currencyCode: String = "ILS"
    /// When the user last updated this balance, so the dashboard can flag stale values.
    var lastUpdated: Date = Date.now
    /// Marks the user's go-to account. The "new transaction" sheet uses
    /// this as the default account so the common case is one tap. At
    /// most one account should carry this flag at a time; the editor
    /// flow clears it off the others when a new favourite is picked.
    var isFavorite: Bool = false

    /// Transactions linked to this account. Deleting the account just nullifies
    /// the link on its transactions rather than deleting them.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    var transactions: [Transaction] = []

    /// Transfers that *credit* this account (its role as the destination
    /// side of a money move). Declared explicitly so SwiftData can tell
    /// the two Account↔Transaction relationships apart — with more than
    /// one link between the same models the inverse can't be inferred.
    /// Nullify (not cascade): deleting the destination account shouldn't
    /// delete the transfer row, just orphan its destination link.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.destinationAccount)
    var incomingTransfers: [Transaction] = []

    /// Holdings (stocks, ETFs, etc.) inside an investment-type account.
    /// Non-investment accounts simply leave this empty. Deleting the
    /// account cascades into its holdings — they don't make sense on
    /// their own. For non-investment accounts `balance` is the whole
    /// account; for investment accounts it's the liquid-cash component
    /// and the holdings are summed on top.
    @Relationship(deleteRule: .cascade, inverse: \Holding.account)
    var holdings: [Holding] = []

    init(
        name: String = "",
        type: AccountType = .current,
        balance: Decimal = 0,
        currencyCode: String = "ILS",
        lastUpdated: Date = .now,
        isFavorite: Bool = false
    ) {
        self.name = name
        self.type = type
        self.balance = balance
        self.currencyCode = currencyCode
        self.lastUpdated = lastUpdated
        self.isFavorite = isFavorite
    }
}
