import Foundation

#if DEBUG

// MARK: - Blueprint types
//
// The declarative half of the demo data: *what* each scenario contains, with
// no SwiftData in sight. `DemoDataService` owns the *how* — it walks the months,
// rolls the balances and writes the rows. Keeping the two apart means a new
// scenario is a block of plain data at the bottom of this file, not new logic.

/// Everything one scenario is made of.
struct DemoBlueprint {
    var profileName: String
    var profession: String
    var goalsText: String
    var accounts: [DemoAccountSpec]
    var incomes: [DemoRecurringSpec] = []
    var expenses: [DemoRecurringSpec] = []
    /// Bills that land once a year (car test, annual insurance, the summer
    /// holiday) — the lines that make a yearly budget view worth swiping to.
    var annual: [DemoAnnualSpec] = []
    /// Discretionary spending, generated at a different count and size every
    /// month so month-over-month comparisons and "records" have real variance.
    var randomSpends: [DemoRandomSpendSpec] = []
    /// Money moved between the user's own accounts, every month.
    var transfers: [DemoTransferSpec] = []
    var goals: [DemoGoalSpec] = []
    /// The account a wallet is topped up from when it runs dry, and the one a
    /// scenario is "run from" generally.
    var primaryAccountKey: String
    var totalXP: Int = 0
    var streak: Int = 0
}

/// An account to create. `key` is how the other specs refer to it — a plain
/// string rather than a model reference, since nothing exists yet when the
/// blueprint is written.
struct DemoAccountSpec {
    var key: String
    var name: String
    var type: AccountType
    var currency: String = "ILS"
    var isFavorite: Bool = false
    /// The balance the account starts the simulated history with. Used as-is
    /// for wallets and deposits (a deposit's principal is what its interest is
    /// computed on, so it can't be back-solved).
    var openingBalance: Decimal = 0
    /// What the account should be worth **today**, for accounts where that's
    /// the number worth controlling. `DemoDataService` back-solves the opening
    /// balance from it, so the ledger genuinely adds up to what the dashboard
    /// shows instead of the two being typed independently.
    var targetClosingBalance: Decimal?
    /// Wallets (ביט, פייבוקס) hold a float, not a salary: when one is about to
    /// go overdrawn the generator moves money in from the primary account,
    /// which is what a person actually does. Without it a wallet that only ever
    /// pays out ends the history tens of thousands in the red.
    var topUpWhenEmpty: Bool = false
    var deposit: DemoDepositSpec?
}

/// Deposit terms for a savings account, expressed relative to "now" so a
/// scenario keeps making sense whenever it's deployed.
struct DemoDepositSpec {
    var kind: DepositKind = .oneTime
    var ratePercent: Decimal
    /// How far back the deposit was opened.
    var startMonthsAgo: Int
    /// Term length. Negative arithmetic is fine: a deposit opened 18 months ago
    /// on a 12-month term has already matured and will be owed a payout, which
    /// is exactly the state the maturity prompt is for.
    var termMonths: Int
    var autoPayout: Bool = false
    /// Key of the account it pays out into (an עו״ש, per `HomeView`'s rule).
    var payoutAccountKey: String?
}

/// Something that happens on the same day every month — salary, rent, the gym.
struct DemoRecurringSpec {
    var title: String
    var amount: Decimal
    var day: Int
    var accountKey: String
    var categoryName: String?
    /// Percent the amount may swing either way, so two years of salary aren't
    /// the same figure to the shekel.
    var jitter: Int = 0
}

/// A once-a-year bill, pinned to a calendar month.
struct DemoAnnualSpec {
    var title: String
    var amount: Decimal
    var day: Int
    var month: Int
    var accountKey: String
    var categoryName: String
}

/// A bucket of discretionary spending: N rows a month, each somewhere in a
/// range, titled from a small pool so the list reads like a real ledger.
struct DemoRandomSpendSpec {
    var categoryName: String
    var titles: [String]
    var countRange: ClosedRange<Int>
    var amountRange: ClosedRange<Int>
    var accountKey: String
    /// What the matching budget line is called, and what it plans per month.
    var plannedLabel: String
    var plannedMonthlyAmount: Decimal
}

/// A monthly transfer between the user's own accounts.
struct DemoTransferSpec {
    var fromKey: String
    var toKey: String
    var day: Int
    var amount: Decimal
    var title: String
    /// How many of the most recent months this transfer ran for. Lets a
    /// savings plan start part-way into the history rather than on day one.
    var months: Int
}

struct DemoGoalSpec {
    var title: String
    var target: Decimal
    var saved: Decimal
    var monthsAhead: Int?
    var note: String = ""
}

// MARK: - The scenarios

/// The four demo lives. Data only — see `DemoDataService` for what's done with
/// it, and `DemoScenario` for what each one is meant to exercise.
enum DemoScenarioLibrary {

    static func blueprint(for scenario: DemoScenario) -> DemoBlueprint {
        switch scenario {
        case .youngProfessional: return youngProfessional
        case .family:            return family
        case .saver:             return saver
        case .freelancer:        return freelancer
        }
    }

    // MARK: בתחילת הדרך

    /// The simplest shape the app supports: one salary, one current account, a
    /// wallet, and an open-ended savings pot with no terms at all — the case
    /// that must keep working now that deposits have two kinds.
    private static var youngProfessional: DemoBlueprint {
        DemoBlueprint(
            profileName: "נועה",
            profession: "מעצבת גרפית",
            goalsText: "לסגור את המינוס ולחסוך לטיול הגדול",
            accounts: [
                DemoAccountSpec(key: "current", name: "עו״ש לאומי", type: .current, isFavorite: true, targetClosingBalance: 9_500),
                DemoAccountSpec(key: "wallet", name: "ביט", type: .digitalWallet, openingBalance: 280, topUpWhenEmpty: true),
                DemoAccountSpec(key: "savings", name: "חיסכון לטיול", type: .savings, openingBalance: 3_000)
            ],
            incomes: [
                DemoRecurringSpec(title: "משכורת", amount: 11_400, day: 10, accountKey: "current", categoryName: "משכורת", jitter: 4)
            ],
            expenses: [
                DemoRecurringSpec(title: "שכר דירה", amount: 4_200, day: 1, accountKey: "current", categoryName: "שכירות"),
                DemoRecurringSpec(title: "חשמל, מים וארנונה", amount: 520, day: 15, accountKey: "current", categoryName: "חשבונות", jitter: 18),
                DemoRecurringSpec(title: "רב קו", amount: 225, day: 5, accountKey: "current", categoryName: "תחבורה ציבורית"),
                DemoRecurringSpec(title: "מנוי חדר כושר", amount: 199, day: 3, accountKey: "current", categoryName: "כושר גופני")
            ],
            randomSpends: [
                DemoRandomSpendSpec(
                    categoryName: "כלכלת בית",
                    titles: ["סופר", "מכולת", "שוק", "ירקן"],
                    countRange: 4...7,
                    amountRange: 90...420,
                    accountKey: "current",
                    plannedLabel: "קניות לבית",
                    plannedMonthlyAmount: 1_400
                ),
                DemoRandomSpendSpec(
                    categoryName: "מסעדות ובתי קפה",
                    titles: ["קפה", "ארוחת צהריים", "משלוח", "בראנץ׳"],
                    countRange: 3...8,
                    amountRange: 35...190,
                    accountKey: "wallet",
                    plannedLabel: "אוכל בחוץ",
                    plannedMonthlyAmount: 600
                ),
                DemoRandomSpendSpec(
                    categoryName: "בילויים",
                    titles: ["קולנוע", "הופעה", "בר", "יציאה עם חברים"],
                    countRange: 1...4,
                    amountRange: 60...260,
                    accountKey: "current",
                    plannedLabel: "בילויים",
                    plannedMonthlyAmount: 450
                ),
                DemoRandomSpendSpec(
                    categoryName: "אופנה וביגוד",
                    titles: ["חנות בגדים", "נעליים", "קניות אונליין"],
                    countRange: 0...2,
                    amountRange: 120...560,
                    accountKey: "current",
                    plannedLabel: "ביגוד",
                    plannedMonthlyAmount: 300
                )
            ],
            transfers: [
                DemoTransferSpec(fromKey: "current", toKey: "savings", day: 12, amount: 2_200, title: "הפקדה לחיסכון", months: 240)
            ],
            goals: [
                DemoGoalSpec(title: "טיול בדרום אמריקה", target: 25_000, saved: 9_400, monthsAhead: 14, note: "שלושה חודשים, פברואר הבא"),
                DemoGoalSpec(title: "קרן חירום", target: 20_000, saved: 4_800, monthsAhead: 24)
            ],
            primaryAccountKey: "current",
            totalXP: 210,
            streak: 4
        )
    }

    // MARK: משפחה עם ילדים

    /// Two incomes, a foreign-currency account, annual bills, and a children's
    /// savings plan that takes a deposit every month — the replenishable
    /// deposit in its natural habitat.
    private static var family: DemoBlueprint {
        DemoBlueprint(
            profileName: "רותם",
            profession: "מהנדס תוכנה",
            goalsText: "לעבור לדירה גדולה יותר ולחסוך ללימודים של הילדים",
            accounts: [
                DemoAccountSpec(key: "current", name: "עו״ש משותף", type: .current, isFavorite: true, targetClosingBalance: 62_000),
                DemoAccountSpec(key: "wallet", name: "ביט", type: .digitalWallet, openingBalance: 540, topUpWhenEmpty: true),
                DemoAccountSpec(key: "usd", name: "חשבון דולרי", type: .current, currency: "USD", openingBalance: 3_200),
                DemoAccountSpec(
                    key: "kids",
                    name: "תוכנית חיסכון לילדים",
                    type: .savings,
                    openingBalance: 12_000,
                    deposit: DemoDepositSpec(
                        kind: .replenishable,
                        ratePercent: 3.5,
                        startMonthsAgo: 22,
                        termMonths: 24,
                        payoutAccountKey: "current"
                    )
                )
            ],
            incomes: [
                DemoRecurringSpec(title: "משכורת", amount: 18_500, day: 10, accountKey: "current", categoryName: "משכורת", jitter: 3),
                DemoRecurringSpec(title: "משכורת בת/בן הזוג", amount: 11_200, day: 1, accountKey: "current", categoryName: "משכורת", jitter: 5)
            ],
            expenses: [
                DemoRecurringSpec(title: "משכנתא", amount: 7_450, day: 2, accountKey: "current", categoryName: "שכירות"),
                DemoRecurringSpec(title: "חשבונות הבית", amount: 1_250, day: 15, accountKey: "current", categoryName: "חשבונות", jitter: 22),
                DemoRecurringSpec(title: "גן וצהרון", amount: 3_100, day: 5, accountKey: "current", categoryName: "לימודים"),
                DemoRecurringSpec(title: "ביטוח בריאות", amount: 780, day: 8, accountKey: "current", categoryName: "ביטוחים"),
                DemoRecurringSpec(title: "ליסינג ודלק", amount: 2_150, day: 20, accountKey: "current", categoryName: "הוצאות רכב", jitter: 12),
                DemoRecurringSpec(title: "חוגים לילדים", amount: 640, day: 6, accountKey: "current", categoryName: "כושר גופני")
            ],
            annual: [
                DemoAnnualSpec(title: "ביטוח רכב שנתי", amount: 4_200, day: 14, month: 3, accountKey: "current", categoryName: "ביטוחים"),
                DemoAnnualSpec(title: "טסט וטיפול שנתי", amount: 1_850, day: 9, month: 11, accountKey: "current", categoryName: "הוצאות רכב"),
                DemoAnnualSpec(title: "חופשה משפחתית", amount: 14_500, day: 4, month: 8, accountKey: "current", categoryName: "חופשות")
            ],
            randomSpends: [
                DemoRandomSpendSpec(
                    categoryName: "כלכלת בית",
                    titles: ["סופר", "שופרסל", "שוק", "פארם", "ירקן"],
                    countRange: 8...14,
                    amountRange: 120...780,
                    accountKey: "current",
                    plannedLabel: "קניות לבית",
                    plannedMonthlyAmount: 4_200
                ),
                DemoRandomSpendSpec(
                    categoryName: "מסעדות ובתי קפה",
                    titles: ["משלוח", "מסעדה עם הילדים", "קפה", "פלאפל"],
                    countRange: 2...6,
                    amountRange: 70...420,
                    accountKey: "wallet",
                    plannedLabel: "אוכל בחוץ",
                    plannedMonthlyAmount: 900
                ),
                DemoRandomSpendSpec(
                    categoryName: "בריאות",
                    titles: ["מרפאה", "בית מרקחת", "רופא שיניים"],
                    countRange: 1...3,
                    amountRange: 80...520,
                    accountKey: "current",
                    plannedLabel: "בריאות",
                    plannedMonthlyAmount: 400
                ),
                DemoRandomSpendSpec(
                    categoryName: "מתנות",
                    titles: ["מתנת יום הולדת", "מתנה לחתונה", "מתנה לגן"],
                    countRange: 0...3,
                    amountRange: 100...450,
                    accountKey: "wallet",
                    plannedLabel: "מתנות",
                    plannedMonthlyAmount: 350
                ),
                DemoRandomSpendSpec(
                    categoryName: "אופנה וביגוד",
                    titles: ["בגדים לילדים", "נעליים", "קניות אונליין"],
                    countRange: 1...4,
                    amountRange: 150...700,
                    accountKey: "current",
                    plannedLabel: "ביגוד",
                    plannedMonthlyAmount: 800
                )
            ],
            transfers: [
                // Every one of these opens its own sub-deposit inside the
                // children's plan, each with its own 24-month term.
                DemoTransferSpec(fromKey: "current", toKey: "kids", day: 11, amount: 4_000, title: "הפקדה לחיסכון הילדים", months: 22)
            ],
            goals: [
                DemoGoalSpec(title: "מעבר דירה", target: 400_000, saved: 128_000, monthsAhead: 36, note: "הון עצמי לדירה גדולה יותר"),
                DemoGoalSpec(title: "רכב משפחתי", target: 120_000, saved: 34_000, monthsAhead: 18),
                DemoGoalSpec(title: "חופשה בחו״ל", target: 30_000, saved: 30_000, monthsAhead: nil, note: "הושלם")
            ],
            primaryAccountKey: "current",
            totalXP: 880,
            streak: 11
        )
    }

    // MARK: חוסך עם פיקדונות

    /// A shelf of deposits in every state at once: one matured and waiting for
    /// the payout prompt, one still running, a monthly savings plan whose
    /// ladder is dozens of rungs deep, and a foreign-currency account on top.
    private static var saver: DemoBlueprint {
        DemoBlueprint(
            profileName: "דנה",
            profession: "רואת חשבון",
            goalsText: "לפרוש מוקדם ולחיות מהריבית",
            accounts: [
                DemoAccountSpec(key: "current", name: "עו״ש דיסקונט", type: .current, isFavorite: true, targetClosingBalance: 54_000),
                DemoAccountSpec(key: "wallet", name: "פייבוקס", type: .digitalWallet, openingBalance: 190, topUpWhenEmpty: true),
                DemoAccountSpec(key: "usd", name: "חשבון דולרי", type: .current, currency: "USD", openingBalance: 5_400),
                DemoAccountSpec(
                    key: "matured",
                    name: "פיקדון שנתי",
                    type: .savings,
                    openingBalance: 60_000,
                    deposit: DemoDepositSpec(
                        ratePercent: 4.2,
                        startMonthsAgo: 13,
                        // Matured last month and still holding the money, so the
                        // dashboard raises the maturity prompt on first appear.
                        termMonths: 12,
                        payoutAccountKey: "current"
                    )
                ),
                DemoAccountSpec(
                    key: "running",
                    name: "פיקדון שנתיים",
                    type: .savings,
                    openingBalance: 40_000,
                    deposit: DemoDepositSpec(
                        ratePercent: 4.8,
                        startMonthsAgo: 8,
                        termMonths: 24,
                        autoPayout: true,
                        payoutAccountKey: "current"
                    )
                ),
                DemoAccountSpec(
                    key: "plan",
                    name: "תוכנית חיסכון חודשית",
                    type: .savings,
                    openingBalance: 15_000,
                    deposit: DemoDepositSpec(
                        kind: .replenishable,
                        ratePercent: 3.9,
                        startMonthsAgo: 30,
                        termMonths: 36,
                        payoutAccountKey: "current"
                    )
                )
            ],
            incomes: [
                DemoRecurringSpec(title: "משכורת", amount: 22_500, day: 9, accountKey: "current", categoryName: "משכורת", jitter: 3),
                DemoRecurringSpec(title: "דיבידנד רבעוני", amount: 2_400, day: 22, accountKey: "current", categoryName: "הכנסה נוספת", jitter: 35)
            ],
            expenses: [
                DemoRecurringSpec(title: "שכר דירה", amount: 6_100, day: 1, accountKey: "current", categoryName: "שכירות"),
                DemoRecurringSpec(title: "חשבונות", amount: 890, day: 15, accountKey: "current", categoryName: "חשבונות", jitter: 20),
                DemoRecurringSpec(title: "ביטוחים", amount: 610, day: 7, accountKey: "current", categoryName: "ביטוחים"),
                DemoRecurringSpec(title: "מנוי תחבורה", amount: 280, day: 4, accountKey: "current", categoryName: "תחבורה ציבורית")
            ],
            annual: [
                DemoAnnualSpec(title: "חופשה בחו״ל", amount: 11_000, day: 12, month: 6, accountKey: "current", categoryName: "חופשות"),
                DemoAnnualSpec(title: "ביטוח דירה", amount: 1_400, day: 3, month: 2, accountKey: "current", categoryName: "ביטוחים")
            ],
            randomSpends: [
                DemoRandomSpendSpec(
                    categoryName: "כלכלת בית",
                    titles: ["סופר", "מכולת", "שוק"],
                    countRange: 5...9,
                    amountRange: 110...520,
                    accountKey: "current",
                    plannedLabel: "קניות לבית",
                    plannedMonthlyAmount: 2_200
                ),
                DemoRandomSpendSpec(
                    categoryName: "מסעדות ובתי קפה",
                    titles: ["מסעדה", "קפה", "משלוח"],
                    countRange: 2...7,
                    amountRange: 60...340,
                    accountKey: "wallet",
                    plannedLabel: "אוכל בחוץ",
                    plannedMonthlyAmount: 800
                ),
                DemoRandomSpendSpec(
                    categoryName: "קניית ני״ע",
                    titles: ["קניית ETF עוקב S&P", "קניית מניה", "קניית אג״ח ממשלתי"],
                    countRange: 0...2,
                    amountRange: 2_000...9_000,
                    accountKey: "current",
                    plannedLabel: "השקעות",
                    plannedMonthlyAmount: 5_000
                ),
                DemoRandomSpendSpec(
                    categoryName: "טיפוח",
                    titles: ["מספרה", "קוסמטיקה"],
                    countRange: 0...2,
                    amountRange: 90...380,
                    accountKey: "wallet",
                    plannedLabel: "טיפוח",
                    plannedMonthlyAmount: 250
                )
            ],
            transfers: [
                DemoTransferSpec(fromKey: "current", toKey: "plan", day: 13, amount: 6_000, title: "הפקדה חודשית לתוכנית", months: 30)
            ],
            goals: [
                DemoGoalSpec(title: "פרישה מוקדמת", target: 1_000_000, saved: 268_000, monthsAhead: 120, note: "היעד הגדול"),
                DemoGoalSpec(title: "שיפוץ הדירה", target: 90_000, saved: 41_000, monthsAhead: 20)
            ],
            primaryAccountKey: "current",
            totalXP: 2_150,
            streak: 23
        )
    }

    // MARK: עצמאי

    /// Income that arrives in lumps and never the same one twice, plus
    /// securities trades on both sides and a short deposit set to pay out on
    /// its own — the auto-payout path.
    private static var freelancer: DemoBlueprint {
        DemoBlueprint(
            profileName: "יונתן",
            profession: "צלם עצמאי",
            goalsText: "להחזיק שישה חודשי הוצאות בצד ולקנות ציוד חדש",
            accounts: [
                DemoAccountSpec(key: "business", name: "עו״ש עסקי", type: .current, isFavorite: true, targetClosingBalance: 31_000),
                DemoAccountSpec(key: "personal", name: "עו״ש פרטי", type: .current, targetClosingBalance: 6_500),
                DemoAccountSpec(key: "wallet", name: "ביט", type: .digitalWallet, openingBalance: 130, topUpWhenEmpty: true),
                DemoAccountSpec(
                    key: "deposit",
                    name: "פיקדון רבעוני",
                    type: .savings,
                    openingBalance: 25_000,
                    deposit: DemoDepositSpec(
                        ratePercent: 4.0,
                        startMonthsAgo: 4,
                        termMonths: 6,
                        autoPayout: true,
                        payoutAccountKey: "business"
                    )
                )
            ],
            expenses: [
                DemoRecurringSpec(title: "שכר דירה", amount: 4_900, day: 1, accountKey: "personal", categoryName: "שכירות"),
                DemoRecurringSpec(title: "חשבונות", amount: 690, day: 15, accountKey: "personal", categoryName: "חשבונות", jitter: 25),
                DemoRecurringSpec(title: "ביטוח לאומי", amount: 1_180, day: 15, accountKey: "business", categoryName: "ביטוחים"),
                DemoRecurringSpec(title: "רואה חשבון", amount: 750, day: 20, accountKey: "business", categoryName: "חשבונות"),
                DemoRecurringSpec(title: "מקדמות מס", amount: 3_500, day: 16, accountKey: "business", categoryName: "חשבונות", jitter: 15),
                DemoRecurringSpec(title: "מנוי לתוכנות עריכה", amount: 320, day: 8, accountKey: "business", categoryName: "חשבונות")
            ],
            annual: [
                DemoAnnualSpec(title: "ביטוח ציוד שנתי", amount: 2_900, day: 10, month: 4, accountKey: "business", categoryName: "ביטוחים"),
                DemoAnnualSpec(title: "השתלמות מקצועית", amount: 5_400, day: 18, month: 10, accountKey: "business", categoryName: "לימודים")
            ],
            randomSpends: [
                DemoRandomSpendSpec(
                    categoryName: "כלכלת בית",
                    titles: ["סופר", "מכולת"],
                    countRange: 4...8,
                    amountRange: 80...380,
                    accountKey: "personal",
                    plannedLabel: "קניות לבית",
                    plannedMonthlyAmount: 1_300
                ),
                DemoRandomSpendSpec(
                    categoryName: "הוצאות רכב",
                    titles: ["דלק", "חניה", "כביש 6"],
                    countRange: 3...7,
                    amountRange: 40...460,
                    accountKey: "business",
                    plannedLabel: "נסיעות לצילומים",
                    plannedMonthlyAmount: 1_100
                ),
                DemoRandomSpendSpec(
                    categoryName: "קניית ני״ע",
                    titles: ["קניית ETF", "קניית מניה"],
                    countRange: 0...1,
                    amountRange: 3_000...8_000,
                    accountKey: "business",
                    plannedLabel: "השקעות",
                    plannedMonthlyAmount: 2_500
                ),
                DemoRandomSpendSpec(
                    categoryName: "מסעדות ובתי קפה",
                    titles: ["קפה בדרך", "ארוחה בצילומים"],
                    countRange: 2...6,
                    amountRange: 30...150,
                    accountKey: "wallet",
                    plannedLabel: "אוכל בחוץ",
                    plannedMonthlyAmount: 450
                )
            ],
            transfers: [
                DemoTransferSpec(fromKey: "business", toKey: "personal", day: 5, amount: 7_000, title: "משיכת בעלים", months: 240)
            ],
            goals: [
                DemoGoalSpec(title: "כרית ביטחון לשישה חודשים", target: 150_000, saved: 62_000, monthsAhead: 30),
                DemoGoalSpec(title: "מצלמה חדשה", target: 28_000, saved: 11_500, monthsAhead: 8)
            ],
            primaryAccountKey: "business",
            totalXP: 640,
            streak: 7
        )
    }

    // MARK: - Irregular income
    //
    // The freelancer's invoices can't be a `DemoRecurringSpec` — they arrive
    // two to five times a month at wildly different sizes, which is the whole
    // point of the scenario. `DemoDataService` reads this directly.

    /// Invoice-shaped income for a scenario, or `nil` when its income is the
    /// ordinary monthly kind.
    static func invoices(for scenario: DemoScenario) -> DemoRandomIncomeSpec? {
        switch scenario {
        case .freelancer:
            return DemoRandomIncomeSpec(
                categoryName: "הכנסה נוספת",
                titles: ["חשבונית — צילומי אירוע", "חשבונית — צילומי מוצר", "חשבונית — חתונה", "חשבונית — קמפיין"],
                countRange: 2...4,
                amountRange: 2_500...9_500,
                accountKey: "business",
                plannedLabel: "הכנסה מחשבוניות",
                plannedMonthlyAmount: 26_000
            )
        case .youngProfessional, .family, .saver:
            return nil
        }
    }
}

/// Income that arrives in lumps rather than on a fixed day — the mirror image
/// of `DemoRandomSpendSpec`.
struct DemoRandomIncomeSpec {
    var categoryName: String
    var titles: [String]
    var countRange: ClosedRange<Int>
    var amountRange: ClosedRange<Int>
    var accountKey: String
    var plannedLabel: String
    var plannedMonthlyAmount: Decimal
}

#endif
