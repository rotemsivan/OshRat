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
        // The tests run inside the dev app and share its stored queue: leave
        // it empty, or a simulator run would find test payments waiting.
        defer { router.removeExpired(now: .distantFuture) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        router.receive(PaymentPrefill(amount: 10, merchant: "A", receivedAt: now))
        #expect(router.take(now: now.addingTimeInterval(60))?.merchant == "A")
        #expect(router.take(now: now.addingTimeInterval(61)) == nil)

        router.receive(PaymentPrefill(amount: 10, merchant: "B", receivedAt: now))
        #expect(router.take(now: now.addingTimeInterval(PaymentPrefill.freshness + 1)) == nil)
    }

    /// A second payment arriving while the first still waits must queue
    /// behind it, not replace it — and a stale one in front is skipped.
    @Test func paymentsWaitingTogetherAreHandedOverInOrder() {
        let router = IncomingPaymentRouter.shared
        // The tests run inside the dev app and share its stored queue: leave
        // it empty, or a simulator run would find test payments waiting.
        defer { router.removeExpired(now: .distantFuture) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        while router.take(now: now) != nil {}

        router.receive(PaymentPrefill(amount: 10, merchant: "Stale", receivedAt: now.addingTimeInterval(-PaymentPrefill.freshness - 1)))
        router.receive(PaymentPrefill(amount: 10, merchant: "A", receivedAt: now))
        router.receive(PaymentPrefill(amount: 20, merchant: "B", receivedAt: now))
        #expect(router.pending?.merchant == "Stale")
        #expect(router.take(now: now)?.merchant == "A")
        #expect(router.pending?.merchant == "B")
        #expect(router.take(now: now)?.merchant == "B")
        #expect(router.pending == nil)
    }

    // MARK: Checking the setup

    /// Amount and merchant make a working automation; the card is optional.
    @Test func amountAndMerchantPassTheSetupCheckWithOrWithoutACard() {
        #expect(PaymentPrefill(amount: 42, merchant: "Cafe", cardName: "Visa 1234").setupVerdict == .working)
        #expect(PaymentPrefill(amount: 42, merchant: "Cafe", cardName: nil).setupVerdict == .working)
    }

    /// Nothing usable at all means the fields aren't tied to the payment —
    /// blank strings from an unfilled variable included.
    @Test func aPaymentWithNothingInItIsAnEmptySetup() {
        #expect(PaymentPrefill(amount: nil, merchant: nil, cardName: nil).setupVerdict == .empty)
        #expect(PaymentPrefill(amount: 0, merchant: "  ", cardName: "").setupVerdict == .empty)
    }

    /// A field wired to the whole Shortcut Input sends text that isn't a
    /// number: the amount counts as missing even though something arrived.
    @Test func anUnreadableAmountIsReportedMissing() {
        let raw = "Cafe Nero 42"
        let payment = PaymentPrefill(
            amount: nil, merchant: "Cafe Nero", cardName: "Visa",
            rawAmount: raw
        )
        #expect(!payment.arrived(.amount))
        #expect(payment.setupVerdict == .missing([.amount]))
    }

    @Test func eachMissingRequiredFieldIsListedInOrder() {
        #expect(PaymentPrefill(amount: 42, merchant: nil, cardName: nil).setupVerdict == .missing([.merchant]))
        #expect(PaymentPrefill(amount: nil, merchant: nil, cardName: "Visa").setupVerdict == .missing([.amount, .merchant]))
    }

    /// The newest delivery is remembered after it leaves the queue, for the
    /// setup screen's live check.
    @Test func theLastDeliveredPaymentOutlivesTheQueue() {
        let router = IncomingPaymentRouter.shared
        defer { router.removeExpired(now: .distantFuture) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        while router.take(now: now) != nil {}

        router.receive(PaymentPrefill(amount: 10, merchant: "A", receivedAt: now))
        router.receive(PaymentPrefill(amount: 20, merchant: "B", receivedAt: now))
        while router.take(now: now) != nil {}
        #expect(router.lastReceived?.merchant == "B")
    }

    // MARK: Two processes, one queue

    /// The extension appends straight to the stored queue while the app holds
    /// its own mirror of it. The app's next change re-reads the disk, so the
    /// payment it never saw survives — and the next reload counts it as an
    /// arrival, which ends a snooze.
    @Test func aPaymentSavedByTheOtherProcessSurvivesTheAppsNextChange() {
        let router = IncomingPaymentRouter.shared
        defer { router.removeExpired(now: .distantFuture) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        while router.take(now: now) != nil {}

        router.receive(PaymentPrefill(amount: 10, merchant: "Seen", receivedAt: now))
        // Written as the extension writes, behind the router's back.
        PaymentInbox.append(PaymentPrefill(amount: 20, merchant: "Unseen", receivedAt: now))

        let requests = router.presentationRequests
        #expect(router.take(now: now)?.merchant == "Seen")
        #expect(PaymentInbox.load().map(\.merchant) == ["Unseen"])

        router.reload()
        #expect(router.pending?.merchant == "Unseen")
        // One arrival, whichever of `take` and `reload` noticed it first.
        #expect(router.presentationRequests == requests + 1)
    }

    /// An update installed over a build without the App Group finds its
    /// waiting payments in the app's own defaults: they move into the shared
    /// queue once, merged by id with whatever is already there.
    @Test func paymentsFromBeforeTheAppGroupMoveIntoIt() throws {
        try #require(PaymentInbox.isShared)
        let router = IncomingPaymentRouter.shared
        defer { router.removeExpired(now: .distantFuture) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        while router.take(now: now) != nil {}

        let alreadyShared = PaymentPrefill(amount: 20, merchant: "Shared", receivedAt: now)
        PaymentInbox.append(alreadyShared)
        let stranded = [
            PaymentPrefill(amount: 10, merchant: "Old", receivedAt: now.addingTimeInterval(-60)),
            alreadyShared,  // both places: kept once
        ]
        UserDefaults.standard.set(try JSONEncoder().encode(stranded), forKey: "pendingPayments")

        PaymentInbox.migrateFromAppDefaultsIfNeeded()
        #expect(PaymentInbox.load().map(\.merchant) == ["Old", "Shared"])
        #expect(UserDefaults.standard.data(forKey: "pendingPayments") == nil)
        router.reload()
    }

    /// Taking a payment and putting it back isn't news: it mustn't end the
    /// snooze the user chose by swiping the sheet away.
    @Test func aPutBackPaymentIsNotAnArrival() {
        let router = IncomingPaymentRouter.shared
        defer { router.removeExpired(now: .distantFuture) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        while router.take(now: now) != nil {}

        router.receive(PaymentPrefill(amount: 10, merchant: "A", receivedAt: now))
        let requests = router.presentationRequests
        let taken = router.take(now: now)
        router.putBack([taken].compactMap { $0 })
        router.reload()
        #expect(router.presentationRequests == requests)
        #expect(router.pending?.merchant == "A")
    }

    // MARK: Reading the amount

    /// The Wallet automation sends the amount as text formatted for the
    /// device; every shape of it reads to the same number and currency.
    @Test(arguments: [
        ("42.90", Decimal(string: "42.90")!, nil),
        ("\u{200F}42.90\u{00A0}\u{200F}₪", Decimal(string: "42.90")!, "ILS"),
        ("₪1,234.50", Decimal(string: "1234.50")!, "ILS"),
        ("1.234,50 €", Decimal(string: "1234.50")!, "EUR"),
        ("42,90 ש״ח", Decimal(string: "42.90")!, "ILS"),
        ("USD 12.00", Decimal(12), "USD"),
        ("$1,200", Decimal(1200), "USD"),
        ("-18.5 ILS", Decimal(string: "18.5")!, "ILS"),
    ] as [(String, Decimal, String?)])
    func amountsAreReadFromShortcutText(text: String, amount: Decimal, code: String?) {
        let parsed = PaymentPrefill.parseAmount(text)
        #expect(parsed?.amount == amount)
        #expect(parsed?.currencyCode == code)
    }

    @Test func textWithoutANumberIsNoAmount() {
        #expect(PaymentPrefill.parseAmount(nil) == nil)
        #expect(PaymentPrefill.parseAmount("") == nil)
        #expect(PaymentPrefill.parseAmount("עסקה") == nil)
    }

    /// Nothing at all arriving is how a disconnected automation shows up.
    @Test func anEmptyPaymentReportsThatNothingArrived() {
        #expect(!PaymentPrefill(amount: nil, merchant: " ", cardName: "").receivedAnything)
        #expect(PaymentPrefill(amount: nil, merchant: "Cafe", cardName: nil).receivedAnything)
    }

    /// A payment waits on disk between the till and the notification tap;
    /// it has to come back exactly as it went in, id included (the id is how
    /// its notification is taken down).
    @Test func aWaitingPaymentSurvivesBeingStored() throws {
        let payment = PaymentPrefill(amount: Decimal(string: "42.90"), currencyCode: "ILS",
                                     merchant: "Cafe Nero", cardName: "Visa 1234", rawAmount: "‏42.90 ‏₪")
        let data = try JSONEncoder().encode([payment])
        let restored = try JSONDecoder().decode([PaymentPrefill].self, from: data)
        #expect(restored == [payment])
    }

    // MARK: Guessing a first visit's category

    /// Chains and plain words, in the Latin spelling issuers send and in
    /// Hebrew; the more specific entry wins ("SUPER-PHARM" isn't groceries).
    @Test(arguments: [
        ("SHUFERSAL DEAL TLV", "כלכלת בית"),
        ("רמי לוי שיווק השקמה", "כלכלת בית"),
        ("SUPER-PHARM RAMAT AVIV", "בריאות"),
        ("AROMA ESPRESSO BAR", "מסעדות ובתי קפה"),
        ("PAZ YELLOW 123", "הוצאות רכב"),
        ("H&M DIZENGOFF", "אופנה וביגוד"),
        ("RAV KAV ONLINE", "תחבורה ציבורית"),
    ])
    func aShopsNameSuggestsItsCategory(merchant: String, category: String) {
        #expect(MerchantCategoryHints.categoryName(forMerchant: merchant) == category)
    }

    @Test func anUnknownShopSuggestsNothing() {
        #expect(MerchantCategoryHints.categoryName(forMerchant: "ACME HOLDINGS") == nil)
        #expect(MerchantCategoryHints.categoryName(forMerchant: "") == nil)
    }

    /// The guess only fills a gap: a shop the user already logged keeps the
    /// category they chose, even when its name suggests another.
    @Test func historyBeatsTheNameGuess() throws {
        let context = try Self.makeContext()
        let account = Account(name: "עו״ש", type: .current)
        let groceries = Category(name: "כלכלת בית", kind: .expense, nature: .need)
        let gifts = Category(name: "מתנות", kind: .expense, nature: .want)
        [groceries, gifts].forEach(context.insert)
        context.insert(account)
        let earlier = Self.paid("שופרסל", merchant: "SHUFERSAL DEAL", card: nil, category: gifts, account: account, day: 1)
        context.insert(earlier)

        let seen = PaymentPrefill.resolve(
            PaymentPrefill(amount: 10, merchant: "SHUFERSAL DEAL", cardName: nil),
            paymentHistory: [earlier], recent: [earlier], accounts: [account], categories: [groceries, gifts]
        )
        #expect(seen.category?.name == "מתנות")

        let firstVisit = PaymentPrefill.resolve(
            PaymentPrefill(amount: 10, merchant: "SHUFERSAL EXPRESS", cardName: nil),
            paymentHistory: [earlier], recent: [earlier], accounts: [account], categories: [groceries, gifts]
        )
        #expect(firstVisit.category?.name == "כלכלת בית")
    }
}
