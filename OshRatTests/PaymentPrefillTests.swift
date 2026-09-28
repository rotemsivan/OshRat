import Testing
import Foundation
import SwiftData
@testable import OshRat

/// A card payment from the Wallet automation, turned into what the
/// "תנועה חדשה" sheet opens with — learning from earlier payments.
@MainActor
struct PaymentPrefillTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: UserProfile.self, Account.self, Holding.self, Category.self,
                Transaction.self, TransactionAttachment.self, BudgetItem.self,
                Goal.self, FXRateSnapshot.self, UserProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static func day(_ n: Int) -> Date {
        Date(timeIntervalSince1970: 1_790_000_000 + Double(n) * 86_400)
    }

    /// A row logged from an earlier payment, as the sheet saves one.
    private static func paid(
        _ title: String, merchant: String?, card: String?,
        category: Category?, account: Account?, day n: Int
    ) -> Transaction {
        let row = Transaction(amount: 10, kind: .expense, date: day(n), title: title, category: category, account: account)
        row.paymentMerchant = merchant
        row.paymentCardName = card
        return row
    }

    @Test func aFirstPaymentUsesTheMerchantAndTheFavouriteAccount() throws {
        let context = try Self.makeContext()
        let current = Account(name: "עו״ש", type: .current)
        let wallet = Account(name: "ביט", type: .digitalWallet)
        wallet.isFavorite = true
        [current, wallet].forEach(context.insert)

        let resolved = PaymentPrefill.resolve(
            PaymentPrefill(amount: 42.9, currencyCode: "ILS", merchant: "  Cafe Nero ", cardName: nil),
            paymentHistory: [], recent: [], accounts: [current, wallet]
        )
        #expect(resolved.title == "Cafe Nero")
        #expect(resolved.category == nil)
        #expect(resolved.account === wallet)
    }

    /// The whole point: the user renamed "SHUFERSAL DEAL" to "סופר" and filed
    /// it under כלכלת בית on the first visit; the second visit arrives that way.
    @Test func aRepeatMerchantBorrowsTheRenamedTitleAndCategory() throws {
        let context = try Self.makeContext()
        let groceries = Category(name: "כלכלת בית", kind: .expense)
        let account = Account(name: "עו״ש", type: .current)
        context.insert(groceries); context.insert(account)
        let older = Self.paid("שופרסל ישן", merchant: "SHUFERSAL DEAL", card: nil, category: nil, account: account, day: 1)
        let newer = Self.paid("סופר", merchant: "SHUFERSAL DEAL", card: nil, category: groceries, account: account, day: 5)
        [older, newer].forEach(context.insert)

        let resolved = PaymentPrefill.resolve(
            // Different case and spacing than last time.
            PaymentPrefill(amount: 120, merchant: "shufersal  deal", cardName: nil),
            paymentHistory: [newer, older], recent: [newer, older], accounts: [account]
        )
        #expect(resolved.title == "סופר")
        #expect(resolved.category === groceries)
    }

    @Test func theCardPicksTheAccountItWasUsedWithLastTime() throws {
        let context = try Self.makeContext()
        let joint = Account(name: "עו״ש משותף", type: .current)
        joint.isFavorite = true
        let personal = Account(name: "עו״ש פרטי", type: .current)
        [joint, personal].forEach(context.insert)
        let earlier = Self.paid("קפה", merchant: "Aroma", card: "Visa 1234", category: nil, account: personal, day: 3)
        context.insert(earlier)

        let resolved = PaymentPrefill.resolve(
            PaymentPrefill(amount: 18, merchant: "Some new shop", cardName: "Visa 1234"),
            paymentHistory: [earlier], recent: [earlier], accounts: [joint, personal]
        )
        #expect(resolved.account === personal)
        // A new merchant still gets its own name, not the other row's title.
        #expect(resolved.title == "Some new shop")
    }

    @Test func aCardWithNoHistoryMatchesAnAccountNamedAfterIt() throws {
        let context = try Self.makeContext()
        let main = Account(name: "עו״ש", type: .current)
        main.isFavorite = true
        let card = Account(name: "כרטיס 1234", type: .current)
        [main, card].forEach(context.insert)

        let resolved = PaymentPrefill.resolve(
            PaymentPrefill(amount: 5, merchant: nil, cardName: "Visa •••• 1234"),
            paymentHistory: [], recent: [], accounts: [main, card]
        )
        #expect(resolved.account === card)
    }

    /// Two accounts mentioning the same word is a guess, not a match.
    @Test func anAmbiguousCardNameFallsBackToTheFavourite() throws {
        let context = try Self.makeContext()
        let a = Account(name: "Max אישי", type: .current)
        let b = Account(name: "Max משפחתי", type: .current)
        b.isFavorite = true
        [a, b].forEach(context.insert)

        let resolved = PaymentPrefill.resolve(
            PaymentPrefill(merchant: nil, cardName: "Max"),
            paymentHistory: [], recent: [], accounts: [a, b]
        )
        #expect(resolved.account === b)
    }

    /// Payments logged by hand before the feature existed still teach it,
    /// through a title that matches the merchant.
    @Test func aHandTypedRowWithTheMerchantsNameIsAPrecedent() throws {
        let context = try Self.makeContext()
        let dining = Category(name: "מסעדות ובתי קפה", kind: .expense)
        let account = Account(name: "עו״ש", type: .current)
        context.insert(dining); context.insert(account)
        let manual = Transaction(amount: 30, kind: .expense, date: Self.day(2), title: "ארומה", category: dining, account: account)
        context.insert(manual)

        let resolved = PaymentPrefill.resolve(
            PaymentPrefill(amount: 30, merchant: "ארומה", cardName: nil),
            paymentHistory: [], recent: [manual], accounts: [account]
        )
        #expect(resolved.title == "ארומה")
        #expect(resolved.category === dining)
    }

    /// Income, transfers and balance corrections aren't precedents for a
    /// payment, and an account that can't pay an expense is never picked.
    @Test func onlyOrdinaryExpensesAndPayingAccountsCount() throws {
        let context = try Self.makeContext()
        let salary = Category(name: "משכורת", kind: .income)
        let current = Account(name: "עו״ש", type: .current)
        let savings = Account(name: "פיקדון", type: .savings)
        [current, savings].forEach(context.insert)
        context.insert(salary)
        let income = Transaction(amount: 900, kind: .income, date: Self.day(4), title: "Acme", category: salary, account: current)
        income.paymentMerchant = "Acme"
        let onSavings = Self.paid("x", merchant: "Other", card: "Visa 9", category: nil, account: savings, day: 5)
        [income, onSavings].forEach(context.insert)

        let resolved = PaymentPrefill.resolve(
            PaymentPrefill(merchant: "Acme", cardName: "Visa 9"),
            paymentHistory: [onSavings, income], recent: [onSavings, income],
            accounts: [current] // what the sheet passes: paying accounts only
        )
        #expect(resolved.category == nil)
        #expect(resolved.title == "Acme")
        #expect(resolved.account === current)
    }

    @Test func blankFieldsFromTheShortcutAreTreatedAsMissing() {
        let payment = PaymentPrefill(amount: nil, currencyCode: nil, merchant: "   ", cardName: "")
        #expect(payment.trimmedMerchant == nil)
        #expect(payment.trimmedCardName == nil)
        let resolved = PaymentPrefill.resolve(payment, paymentHistory: [], recent: [], accounts: [])
        #expect(resolved.title == "")
        #expect(resolved.account == nil)
    }

    @Test func thePendingPaymentIsHandedOverOnceAndOnlyWhileFresh() {
        let router = IncomingPaymentRouter.shared
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        router.receive(PaymentPrefill(amount: 10, merchant: "A", receivedAt: now))
        #expect(router.take(now: now.addingTimeInterval(60))?.merchant == "A")
        #expect(router.take(now: now.addingTimeInterval(61)) == nil)

        router.receive(PaymentPrefill(amount: 10, merchant: "B", receivedAt: now))
        #expect(router.take(now: now.addingTimeInterval(PaymentPrefill.freshness + 1)) == nil)
    }
}
