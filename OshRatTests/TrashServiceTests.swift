import Testing
import Foundation
import SwiftData
@testable import OshRat

/// Soft delete, restore and purge, against a real in-memory store.
///
/// Unlike the other suites here these run against a `ModelContainer` rather
/// than a pure value type — the whole point of `TrashService` is what it does
/// to persisted rows and their relationships, which is exactly where a delete
/// goes wrong if it's going to.
@MainActor
struct TrashServiceTests {

    /// A throwaway store per test. `isStoredInMemoryOnly` keeps it off disk and
    /// gives each test a clean slate.
    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: UserProfile.self, Account.self, Holding.self, Category.self,
                Transaction.self, TransactionAttachment.self, BudgetItem.self,
                Goal.self, FXRateSnapshot.self, UserProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    // MARK: - Soft delete / restore

    @Test func softDeletingAnExpenseGivesTheMoneyBack() throws {
        let context = try Self.makeContext()
        let account = Account(name: "עו״ש", type: .current, balance: 900, currencyCode: "ILS")
        context.insert(account)
        let tx = Transaction(amount: 100, kind: .expense, currencyCode: "ILS", account: account)
        context.insert(tx)

        TrashService.softDelete(tx, fx: nil)
        try context.save()

        #expect(account.balance == 1000)
        #expect(tx.deletedAt != nil)
        // Soft delete keeps the row — that's the whole point.
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    @Test func restoringReappliesTheEffect() throws {
        let context = try Self.makeContext()
        let account = Account(name: "עו״ש", type: .current, balance: 900, currencyCode: "ILS")
        context.insert(account)
        let tx = Transaction(amount: 100, kind: .expense, currencyCode: "ILS", account: account)
        context.insert(tx)

        TrashService.softDelete(tx, fx: nil)
        TrashService.restore(tx, fx: nil)
        try context.save()

        // Round trip has to land exactly where it started.
        #expect(account.balance == 900)
        #expect(tx.deletedAt == nil)
    }

    @Test func softDeletingATransferUnwindsBothSides() throws {
        let context = try Self.makeContext()
        let source = Account(name: "עו״ש", type: .current, balance: 500, currencyCode: "ILS")
        let destination = Account(name: "חיסכון", type: .savings, balance: 1500, currencyCode: "ILS")
        context.insert(source)
        context.insert(destination)
        let transfer = Transaction(
            amount: 500,
            currencyCode: "ILS",
            account: source,
            destinationAccount: destination,
            destinationAmount: 500
        )
        context.insert(transfer)

        TrashService.softDelete(transfer, fx: nil)
        try context.save()

        #expect(source.balance == 1000)
        #expect(destination.balance == 1000)
    }

    // MARK: - Permanent delete

    /// The "delete permanently" path from Recently Deleted. A transaction
    /// carries a cascade relationship to its attachments, so this also checks
    /// the blobs go with it rather than being orphaned.
    @Test func permanentlyDeletingATransactionTakesItsAttachments() throws {
        let context = try Self.makeContext()
        let account = Account(name: "עו״ש", type: .current, balance: 1000, currencyCode: "ILS")
        context.insert(account)
        let tx = Transaction(amount: 100, kind: .expense, currencyCode: "ILS", account: account)
        context.insert(tx)
        let receipt = TransactionAttachment(
            filename: "receipt.pdf",
            data: Data("pretend-pdf".utf8),
            typeIdentifier: "com.adobe.pdf"
        )
        receipt.transaction = tx
        context.insert(receipt)
        try context.save()

        TrashService.softDelete(tx, fx: nil)
        try context.save()

        context.delete(tx)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TransactionAttachment>()) == 0)
        // The account survives, and keeps the balance the soft delete restored.
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 1)
        #expect(account.balance == 1100)
    }

    /// Deleting a transaction must not take its account with it — the
    /// relationship nullifies from the other side.
    @Test func permanentlyDeletingATransferLeavesBothAccounts() throws {
        let context = try Self.makeContext()
        let source = Account(name: "עו״ש", type: .current, balance: 500, currencyCode: "ILS")
        let destination = Account(name: "חיסכון", type: .savings, balance: 1500, currencyCode: "ILS")
        context.insert(source)
        context.insert(destination)
        let transfer = Transaction(
            amount: 500,
            currencyCode: "ILS",
            account: source,
            destinationAccount: destination,
            destinationAmount: 500
        )
        context.insert(transfer)
        try context.save()

        TrashService.softDelete(transfer, fx: nil)
        try context.save()
        context.delete(transfer)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 2)
        #expect(source.transactions.isEmpty)
        #expect(destination.incomingTransfers.isEmpty)
    }

    // MARK: - Purge

    @Test func purgeRemovesOnlyRowsPastTheRetentionWindow() throws {
        let context = try Self.makeContext()
        let account = Account(name: "עו״ש", type: .current, balance: 1000, currencyCode: "ILS")
        context.insert(account)

        let old = Transaction(amount: 10, kind: .expense, currencyCode: "ILS", account: account)
        let recent = Transaction(amount: 20, kind: .expense, currencyCode: "ILS", account: account)
        let live = Transaction(amount: 30, kind: .expense, currencyCode: "ILS", account: account)
        context.insert(old)
        context.insert(recent)
        context.insert(live)

        old.deletedAt = Date.now.addingTimeInterval(-(TrashService.retention + 86400))
        recent.deletedAt = Date.now.addingTimeInterval(-86400)
        try context.save()

        TrashService.purgeExpired(in: context)

        let remaining = try context.fetch(FetchDescriptor<Transaction>())
        #expect(remaining.count == 2)
        #expect(remaining.contains { $0.amount == 20 })
        #expect(remaining.contains { $0.amount == 30 })
    }
}
