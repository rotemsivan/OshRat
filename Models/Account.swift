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

    /// When the account was soft-deleted, or `nil` while it's live.
    /// Deleting an account doesn't remove the row — it hides it (every
    /// account `@Query` filters `deletedAt == nil`) so it can be restored
    /// from "Recently Deleted". `TrashService.purgeExpired` hard-deletes
    /// rows past the retention window. Optional + default `nil` keeps the
    /// change additive and CloudKit-compatible.
    var deletedAt: Date?

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

    // MARK: - Deposit terms
    //
    // A savings account in this app is a *deposit* (פיקדון): an amount put
    // away at a fixed rate until a maturity date, at which point it pays out
    // into another account. The fields below carry those terms. They live on
    // `Account` rather than in a parallel `Deposit` model because a deposit
    // *is* an account — it holds a balance, counts toward net worth, and is
    // the source of a real transfer at payout. A separate model would have
    // duplicated the balance and bypassed the transfer and soft-delete
    // machinery that already works.
    //
    // Every field is optional or defaulted (CloudKit rules, and so existing
    // rows migrate untouched), and all of them are ignored unless
    // `type == .savings`. All-nil is a perfectly good open-ended savings pot:
    // no maturity date means it never matures and never prompts.

    /// Annual nominal rate as a percentage — `4.2` means 4.2% a year.
    var interestRatePercent: Decimal?

    /// When the money was put away. Interest accrues from here.
    var depositStartDate: Date?

    /// The day the deposit pays out. `nil` for an open-ended savings pot.
    var maturityDate: Date?

    /// Whether the payout should happen on its own at maturity, or wait and
    /// ask the user first. Set from the toggle in the account editor.
    var autoPayoutOnMaturity: Bool = false

    /// When this deposit was actually paid out, or `nil` while it's still
    /// running. Doubles as the latch that stops the maturity prompt coming
    /// back once the money has been moved.
    var payoutCompletedAt: Date?

    /// Deposits that pay out into *this* account — the inverse side of
    /// `payoutAccount` below. Declared here (on the to-many side) because a
    /// self-referencing relationship needs its inverse spelled out. Nullify,
    /// not cascade: closing the account the money was going to land in must
    /// not delete the deposit itself, only forget where it was headed (the
    /// prompt then asks the user to pick a target).
    @Relationship(deleteRule: .nullify, inverse: \Account.payoutAccount)
    var incomingDepositPayouts: [Account] = []

    /// Where this deposit's money goes at maturity. `nil` means "not decided
    /// yet" — the maturity prompt asks rather than guessing.
    var payoutAccount: Account?

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
        isFavorite: Bool = false,
        interestRatePercent: Decimal? = nil,
        depositStartDate: Date? = nil,
        maturityDate: Date? = nil,
        autoPayoutOnMaturity: Bool = false,
        payoutAccount: Account? = nil
    ) {
        self.name = name
        self.type = type
        self.balance = balance
        self.currencyCode = currencyCode
        self.lastUpdated = lastUpdated
        self.isFavorite = isFavorite
        self.interestRatePercent = interestRatePercent
        self.depositStartDate = depositStartDate
        self.maturityDate = maturityDate
        self.autoPayoutOnMaturity = autoPayoutOnMaturity
        self.payoutAccount = payoutAccount
    }
}

// MARK: - Deposit

extension Account {
    /// The deposit terms attached to this account, or `nil` when it isn't a
    /// savings account or has no terms worth reading (no rate *and* no
    /// maturity date — an ordinary pot of money).
    ///
    /// Bridges the stored fields to the pure `DepositTerms`, which owns all
    /// the actual maths. `depositStartDate` falls back to `lastUpdated` for
    /// rows written before these fields existed, so interest on a legacy
    /// savings account accrues from a real date rather than 1970.
    var depositTerms: DepositTerms? {
        guard type == .savings, interestRatePercent != nil || maturityDate != nil else { return nil }
        return DepositTerms(
            principal: balance,
            annualRatePercent: interestRatePercent,
            startDate: depositStartDate ?? lastUpdated,
            maturityDate: maturityDate
        )
    }

    /// True for a savings account — a *deposit* (פיקדון) in this app's
    /// language, whether or not terms have been attached to it yet. Distinct
    /// from `depositTerms != nil`, which additionally requires a rate or a
    /// maturity date: an open-ended pot is still a deposit account, it just
    /// has nothing to mature.
    var isDeposit: Bool { type == .savings }

    /// Whether this account may carry the favourite star — see
    /// `AccountType.allowsFavorite`. Every place that *sets* the flag checks
    /// this first, so the invariant is maintained at write time rather than
    /// defended by each view.
    var canBeFavorite: Bool { type.allowsFavorite }

    /// Clears a star this account is no longer entitled to, returning whether
    /// anything changed.
    ///
    /// Needed because the rule arrived after the data did: a savings account
    /// starred before deposits were excluded still holds `isFavorite == true`
    /// in the store, and it would keep drawing a star and keep winning the
    /// "default account" lookups. Healing the row once is simpler than making
    /// every reader defend itself.
    @discardableResult
    func clearFavoriteIfNotAllowed() -> Bool {
        guard isFavorite, !canBeFavorite else { return false }
        isFavorite = false
        return true
    }

    /// True when this deposit has reached its maturity date and the money
    /// hasn't been moved out yet — i.e. it's owed a payout. Soft-deleted
    /// accounts are excluded: a deposit in the trash shouldn't nag.
    func isAwaitingPayout(asOf now: Date = .now) -> Bool {
        guard deletedAt == nil, payoutCompletedAt == nil, let terms = depositTerms else { return false }
        return terms.isMatured(asOf: now)
    }
}
