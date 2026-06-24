import Foundation
import SwiftData

/// Anything that can be soft-deleted carries a `deletedAt` timestamp:
/// `nil` while live, set to the moment of deletion while it sits in
/// "Recently Deleted". `Account` and `Transaction` conform (their stored
/// `deletedAt` property satisfies it); the conformances live here so the
/// model files stay free of trash-specific plumbing.
protocol SoftDeletable: AnyObject {
    var deletedAt: Date? { get set }
}

extension Account: SoftDeletable {}
extension Transaction: SoftDeletable {}

/// Soft-delete / restore / purge for accounts and transactions — the
/// "Recently Deleted" recycle bin.
///
/// Deleting doesn't remove a row; it stamps `deletedAt` so every live
/// `@Query` (which filters `deletedAt == nil`) drops it, while a
/// dedicated `RecentlyDeletedView` query (filtering `deletedAt != nil`)
/// surfaces it for restore. Rows older than `retention` are hard-deleted
/// by `purgeExpired`, called once per dashboard appearance.
///
/// A `@MainActor enum` (no state of its own — the SwiftData store *is*
/// the state) for the same reason as `FXRatesService`: it keeps the
/// `ModelContext` work on the main actor with no cross-actor dance.
@MainActor
enum TrashService {
    /// How long a soft-deleted row stays recoverable before it's purged
    /// for good. Mirrors the platform "Recently Deleted" convention.
    static let retention: TimeInterval = 30 * 24 * 3600   // 30 days

    // MARK: - Transactions

    /// Hide a transaction and undo its effect on the account balance — the
    /// money it moved comes back, exactly as a hard delete used to do. The
    /// row stays in the store (restorable) until purged. The caller saves.
    static func softDelete(_ transaction: Transaction, fx: FXRateSnapshot?) {
        transaction.reverseEffect(using: fx)
        transaction.deletedAt = .now
    }

    /// Bring a transaction back and re-apply its balance effect, reversing
    /// the `softDelete` above so balances stay honest across the round trip.
    static func restore(_ transaction: Transaction, fx: FXRateSnapshot?) {
        transaction.deletedAt = nil
        transaction.reapplyEffect(using: fx)
    }

    // MARK: - Accounts

    /// Hide an account. Its balance simply drops out of the dashboard
    /// totals (those sum only live accounts), so there's no balance math to
    /// undo here — unlike a transaction. A hidden account can't remain the
    /// "favourite" pointer, so that flag is cleared. Its transactions and
    /// holdings stay attached, intact for a later restore.
    static func softDelete(_ account: Account) {
        account.isFavorite = false
        account.deletedAt = .now
    }

    /// Bring an account back. It returns un-favourited; the user can re-pin
    /// it if they want.
    static func restore(_ account: Account) {
        account.deletedAt = nil
    }

    // MARK: - Purge

    /// Hard-delete every soft-deleted row whose `deletedAt` is older than
    /// `retention`. Cheap to run on a hand-entered ledger, so the dashboard
    /// calls it on appearance. Transactions go first, then accounts, so a
    /// purged account's transactions aren't left dangling mid-pass.
    ///
    /// Rows are fetched whole and filtered in Swift rather than via a
    /// `#Predicate` on the optional `deletedAt` — the dataset is tiny by
    /// design, and it sidesteps the optional-comparison quirks of the
    /// predicate builder.
    static func purgeExpired(in context: ModelContext, now: Date = .now) {
        let cutoff = now.addingTimeInterval(-retention)
        purge(Transaction.self, before: cutoff, in: context)
        purge(Account.self, before: cutoff, in: context)
        try? context.save()
    }

    private static func purge<T: PersistentModel & SoftDeletable>(
        _ type: T.Type,
        before cutoff: Date,
        in context: ModelContext
    ) {
        guard let rows = try? context.fetch(FetchDescriptor<T>()) else { return }
        for row in rows {
            if let deletedAt = row.deletedAt, deletedAt < cutoff {
                context.delete(row)
            }
        }
    }
}
