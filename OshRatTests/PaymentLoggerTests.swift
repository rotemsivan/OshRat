import Testing
import Foundation
import SwiftData
@testable import OshRat

/// "רישום כולם" — waiting payments logged without their sheets, and the
/// incomplete ones left in line.
@MainActor
struct PaymentLoggerTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: UserProfile.self, Account.self, Holding.self, Category.self,
                Transaction.self, TransactionAttachment.self, BudgetItem.self,
                Goal.self, FXRateSnapshot.self, UserProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static let paidAt = Date(timeIntervalSince1970: 1_800_000_000)

    /// A complete payment becomes an expense like the sheet's: amount as paid,
    /// the account's balance moved, dated when the card was tapped, and the
    /// raw merchant kept for next time.
    @Test func aCompletePaymentIsLoggedAsAnExpense() throws {
        let context = try Self.makeContext()
        let account = Account(name: "עו״ש", type: .current, balance: 1000)
        let dining = Category(name: "מסעדות", kind: .expense, nature: .want)
        context.insert(account)
        context.insert(dining)
        let payment = PaymentPrefill(amount: Decimal(string: "42.90"), currencyCode: "ILS",
                                     merchant: "Cafe Nero", cardName: "Visa 1234", receivedAt: Self.paidAt)
        let resolved = PaymentPrefill.Resolved(title: "קפה נרו", category: dining, account: account)

        let row = try #require(PaymentLogger.log(payment, resolved, fxSnapshot: nil, in: context,
                                                 now: Self.paidAt.addingTimeInterval(3600)))
        #expect(row.amount == Decimal(string: "42.90"))
        #expect(row.kind == .expense)
        #expect(row.date == Self.paidAt)
        #expect(row.title == "קפה נרו")
        #expect(row.paymentMerchant == "Cafe Nero")
        #expect(account.balance == Decimal(string: "957.10"))
        #expect(row.balanceAfter == account.balance)
    }

    /// What the sheet would refuse to save is left for its sheet: no
    /// category (a first visit), no amount, or no rate into the account's
    /// currency.
    @Test func anIncompletePaymentIsNotLogged() throws {
        let context = try Self.makeContext()
        let account = Account(name: "עו״ש", type: .current, balance: 1000)
        let dining = Category(name: "מסעדות", kind: .expense, nature: .want)
        context.insert(account)
        context.insert(dining)
        let payment = PaymentPrefill(amount: 30, currencyCode: "ILS", merchant: "New shop", cardName: nil)

        let noCategory = PaymentPrefill.Resolved(title: "New shop", category: nil, account: account)
        #expect(PaymentLogger.log(payment, noCategory, fxSnapshot: nil, in: context) == nil)

        let full = PaymentPrefill.Resolved(title: "New shop", category: dining, account: account)
        let noAmount = PaymentPrefill(amount: nil, merchant: "New shop", cardName: nil)
        #expect(PaymentLogger.log(noAmount, full, fxSnapshot: nil, in: context) == nil)

        let inDollars = PaymentPrefill(amount: 30, currencyCode: "USD", merchant: "New shop", cardName: nil)
        #expect(PaymentLogger.log(inDollars, full, fxSnapshot: nil, in: context) == nil)

        #expect(account.balance == 1000)
    }

    /// The incomplete ones go back to the front of the line, in order.
    @Test func takeAllThenPutBackKeepsTheOrder() {
        let router = IncomingPaymentRouter.shared
        // The tests run inside the dev app and share its stored queue: leave
        // it empty, or a simulator run would find test payments waiting.
        defer { router.removeExpired(now: .distantFuture) }
        let now = Self.paidAt
        while router.take(now: now) != nil {}

        let a = PaymentPrefill(amount: 1, merchant: "A", cardName: nil, receivedAt: now)
        let b = PaymentPrefill(amount: 2, merchant: "B", cardName: nil, receivedAt: now)
        let c = PaymentPrefill(amount: 3, merchant: "C", cardName: nil, receivedAt: now)
        [a, b, c].forEach(router.receive)

        let all = router.takeAll(now: now)
        #expect(all.map(\.merchant) == ["A", "B", "C"])
        #expect(router.waitingCount == 0)

        router.putBack([a, c])
        #expect(router.take(now: now)?.merchant == "A")
        #expect(router.take(now: now)?.merchant == "C")
        #expect(router.take(now: now) == nil)
    }

    /// "דילוג" parks a payment: it's still counted, but doesn't come up by
    /// itself — until the list's row asks for the line again.
    @Test func aSkippedPaymentWaitsForReview() {
        let router = IncomingPaymentRouter.shared
        // The tests run inside the dev app and share its stored queue: leave
        // it empty, or a simulator run would find test payments waiting.
        defer { router.removeExpired(now: .distantFuture) }
        let now = Date.now
        router.removeExpired(now: .distantFuture)

        let coffee = PaymentPrefill(amount: 18, merchant: "Aroma", cardName: nil, receivedAt: now)
        router.skip(coffee, now: now)
        #expect(router.pending == nil)
        #expect(router.take(now: now) == nil)
        #expect(router.totalWaitingCount == 1)

        router.requestReview()
        #expect(router.pending?.merchant == "Aroma")
        #expect(router.take(now: now)?.isSkipped == false)
        #expect(router.totalWaitingCount == 0)
    }

    /// Skipped or not, a payment left unlogged past `freshness` is deleted.
    @Test func anUnloggedPaymentIsDeletedAfterAWeek() {
        let router = IncomingPaymentRouter.shared
        // The tests run inside the dev app and share its stored queue: leave
        // it empty, or a simulator run would find test payments waiting.
        defer { router.removeExpired(now: .distantFuture) }
        let now = Date.now
        router.removeExpired(now: .distantFuture)

        let old = PaymentPrefill(amount: 5, merchant: "Old", cardName: nil,
                                 receivedAt: now.addingTimeInterval(-PaymentPrefill.freshness - 60))
        let recent = PaymentPrefill(amount: 6, merchant: "Recent", cardName: nil, receivedAt: now)
        router.skip(old, now: now)
        router.receive(recent)

        let expired = router.removeExpired(now: now)
        #expect(expired.map(\.merchant) == ["Old"])
        #expect(router.totalWaitingCount == 1)
        #expect(router.take(now: now)?.merchant == "Recent")
    }
}
