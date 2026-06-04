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

    /// Transactions linked to this account. Deleting the account just nullifies
    /// the link on its transactions rather than deleting them.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.account)
    var transactions: [Transaction] = []

    init(
        name: String = "",
        type: AccountType = .current,
        balance: Decimal = 0,
        currencyCode: String = "ILS",
        lastUpdated: Date = .now
    ) {
        self.name = name
        self.type = type
        self.balance = balance
        self.currencyCode = currencyCode
        self.lastUpdated = lastUpdated
    }
}
