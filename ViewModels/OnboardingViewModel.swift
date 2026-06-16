import Foundation
import SwiftData

/// Drives the first-launch setup wizard.
///
/// While the user is filling things in we keep everything as plain values
/// (a "draft"). Nothing touches SwiftData until the user finishes the last
/// step and we call `commit(into:)`. That way, abandoning the wizard
/// half-way leaves the database clean — no orphan `UserProfile`, `Account`
/// or `BudgetItem` rows to clean up later.
@Observable
final class OnboardingViewModel {

    // MARK: - Personal details (step 1)

    var name: String = ""
    var profession: String = ""
    var goalsText: String = ""
    var preferredCurrencyCode: String = "ILS"

    // MARK: - Financial accounts (step 2)

    var accountDrafts: [AccountDraft] = []

    // MARK: - Budget (step 3)

    /// Planned monthly income lines: salary, side gigs, etc. The user
    /// names each one freely so the dashboard can show them by name
    /// rather than forcing a generic "income" category.
    var incomeDrafts: [IncomeSourceDraft] = []

    /// Planned expenses, each tied to a category (which knows whether
    /// it's a need or a want). Includes a frequency so a barber every
    /// three weeks can be tracked alongside monthly rent.
    var plannedExpenseDrafts: [PlannedExpenseDraft] = []

    // MARK: - Wizard state

    var step: OnboardingStep = .personalDetails

    /// Whether the "Continue" button on the current step should be enabled.
    /// Each step has its own minimal requirement; this keeps validation
    /// in one place rather than scattered across views.
    var canContinue: Bool {
        switch step {
        case .personalDetails:
            // A name is the only hard requirement — everything else can be
            // edited later from the settings screen.
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .financialAccounts:
            // We want the dashboard to have *something* to show, so require
            // at least one account. A zero-balance account is fine.
            return !accountDrafts.isEmpty
        case .budget:
            // At least one income source is required so the dashboard's
            // planned-vs-actual has a denominator. Planned expenses are
            // optional — some users only plan income at first.
            return !incomeDrafts.isEmpty
        }
    }

    /// Whether the current step is the last one — controls whether the
    /// primary button reads "Continue" or "Finish".
    var isOnLastStep: Bool {
        step == OnboardingStep.allCases.last
    }

    // MARK: - Navigation between steps

    func advance() {
        guard let currentIndex = OnboardingStep.allCases.firstIndex(of: step),
              currentIndex + 1 < OnboardingStep.allCases.count
        else { return }
        step = OnboardingStep.allCases[currentIndex + 1]
    }

    func retreat() {
        guard let currentIndex = OnboardingStep.allCases.firstIndex(of: step),
              currentIndex > 0
        else { return }
        step = OnboardingStep.allCases[currentIndex - 1]
    }

    // MARK: - Account draft helpers

    func addAccount(_ draft: AccountDraft) {
        accountDrafts.append(draft)
        enforceSingleFavourite(promoted: draft.id)
    }

    func update(_ draft: AccountDraft) {
        guard let index = accountDrafts.firstIndex(where: { $0.id == draft.id }) else { return }
        accountDrafts[index] = draft
        enforceSingleFavourite(promoted: draft.id)
    }

    /// Keeps the "only one favourite at a time" invariant on the draft
    /// list. If `promoted` is favoured, every other draft is demoted.
    /// Called from add/update so the rule is enforced wherever drafts
    /// flow in from the editor sheet.
    private func enforceSingleFavourite(promoted id: UUID) {
        guard let promotedIndex = accountDrafts.firstIndex(where: { $0.id == id }),
              accountDrafts[promotedIndex].isFavorite
        else { return }
        for index in accountDrafts.indices where index != promotedIndex {
            if accountDrafts[index].isFavorite {
                accountDrafts[index].isFavorite = false
            }
        }
    }

    func deleteAccounts(at offsets: IndexSet) {
        // `remove(atOffsets:)` is a SwiftUI extension; doing it by hand here
        // keeps the view model dependency-free. Sort descending so each
        // removal doesn't shift the indices we still have to delete.
        for index in offsets.sorted(by: >) {
            accountDrafts.remove(at: index)
        }
    }

    // MARK: - Income draft helpers

    func addIncome(_ draft: IncomeSourceDraft) {
        incomeDrafts.append(draft)
    }

    func update(_ draft: IncomeSourceDraft) {
        guard let index = incomeDrafts.firstIndex(where: { $0.id == draft.id }) else { return }
        incomeDrafts[index] = draft
    }

    func deleteIncome(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            incomeDrafts.remove(at: index)
        }
    }

    // MARK: - Planned-expense draft helpers

    func addExpense(_ draft: PlannedExpenseDraft) {
        plannedExpenseDrafts.append(draft)
    }

    func update(_ draft: PlannedExpenseDraft) {
        guard let index = plannedExpenseDrafts.firstIndex(where: { $0.id == draft.id }) else { return }
        plannedExpenseDrafts[index] = draft
    }

    func deleteExpenses(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            plannedExpenseDrafts.remove(at: index)
        }
    }

    // MARK: - Persistence

    /// Turns the in-memory drafts into real SwiftData rows. Called once,
    /// when the user taps "Finish" on the last step.
    func commit(into context: ModelContext) {
        let profile = UserProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            profession: profession.trimmingCharacters(in: .whitespacesAndNewlines),
            goalsText: goalsText,
            preferredCurrencyCode: preferredCurrencyCode
        )
        context.insert(profile)

        // Only one account can be the favourite — if the user happened
        // to mark several during onboarding, honour the first one and
        // silently clear the rest. The rule lives here so it doesn't
        // need to be re-checked at every call site that creates accounts.
        var favouriteAlreadyAssigned = false
        for draft in accountDrafts {
            let shouldBeFavourite = draft.isFavorite && !favouriteAlreadyAssigned
            if shouldBeFavourite { favouriteAlreadyAssigned = true }
            let account = Account(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: draft.type,
                balance: draft.balance,
                currencyCode: draft.currencyCode,
                lastUpdated: .now,
                isFavorite: shouldBeFavourite
            )
            context.insert(account)

            // Holdings only make sense for investment accounts. If the
            // user typed some and then switched the account type away
            // from .investment, we silently drop them — they were never
            // persisted, so nothing to clean up.
            if draft.type == .investment {
                for holdingDraft in draft.holdings {
                    let holding = Holding(
                        symbol: holdingDraft.symbol.trimmingCharacters(in: .whitespacesAndNewlines),
                        name: holdingDraft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        quantity: holdingDraft.quantity,
                        marketValue: holdingDraft.marketValue,
                        currencyCode: holdingDraft.currencyCode,
                        lastUpdated: .now
                    )
                    // Setting the inverse keeps Account.holdings in sync
                    // automatically — no need to also append it ourselves.
                    holding.account = account
                    context.insert(holding)
                }
            }
        }

        // Income sources — stored as BudgetItem rows with kind=.income
        // and no category (the name carries the source label). Routing
        // through `draft.apply(to:)` keeps this in lockstep with the
        // post-onboarding editor, schedule fields included.
        for draft in incomeDrafts {
            let item = BudgetItem(kind: .income)
            draft.apply(to: item)
            context.insert(item)
        }

        // Planned expenses — stored as BudgetItem rows with kind=.expense
        // and a category. Drop drafts whose category got nilled out (the
        // editor sheet requires one to save, so this is defensive).
        for draft in plannedExpenseDrafts {
            guard draft.category != nil else { continue }
            let item = BudgetItem(kind: .expense)
            draft.apply(to: item)
            context.insert(item)
        }

        // Save explicitly so the gating @Query in ContentView re-fires
        // immediately and the wizard is replaced with the main app.
        try? context.save()
    }
}

/// The discrete steps of the setup wizard, in order.
enum OnboardingStep: CaseIterable {
    case personalDetails
    case financialAccounts
    case budget
}

// MARK: - Account & Holding drafts

/// A draft account being built up in the wizard. We keep this as a plain
/// `struct` (not a SwiftData `@Model`) so that abandoning onboarding
/// doesn't leave half-filled rows in the database.
///
/// For `.investment` accounts, `balance` is treated as the *liquid cash*
/// component, and `holdings` lists the stocks/ETFs/other assets the user
/// holds in that same account. For every other account type, `balance`
/// is the whole account and `holdings` stays empty.
struct AccountDraft: Identifiable, Hashable {
    let id: UUID
    var name: String
    var type: AccountType
    var balance: Decimal
    var currencyCode: String
    var holdings: [HoldingDraft]
    /// Whether the user wants this to be the default account for new
    /// transactions. Persisted onto `Account.isFavorite` at save time;
    /// the save handler is responsible for clearing the flag off any
    /// other account so only one is favourite at a time.
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        name: String = "",
        type: AccountType = .current,
        balance: Decimal = 0,
        currencyCode: String = "ILS",
        holdings: [HoldingDraft] = [],
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.balance = balance
        self.currencyCode = currencyCode
        self.holdings = holdings
        self.isFavorite = isFavorite
    }
}

extension AccountDraft {
    /// Build a draft populated from a persisted Account, so the same
    /// `AccountEditorSheet` can be used to edit an existing account
    /// after onboarding. The draft's `id` is a fresh UUID — it's only
    /// used for SwiftUI list identity, not for matching back to the
    /// persisted account.
    init(from account: Account) {
        self.init(
            name: account.name,
            type: account.type,
            balance: account.balance,
            currencyCode: account.currencyCode,
            holdings: account.holdings.map { HoldingDraft(from: $0) },
            isFavorite: account.isFavorite
        )
    }

    /// Writes this draft back into a persisted Account. Used by the
    /// dashboard's edit-account flow.
    ///
    /// Holdings strategy: **delete-and-recreate**. We don't track which
    /// `HoldingDraft` came from which `Holding`, so the simplest correct
    /// move is to wipe the existing holdings and recreate from the draft.
    /// Downside: every saved edit resets `Holding.lastUpdated`. Worth
    /// switching to a diff-by-persistent-ID strategy once features hang
    /// history (buy/sell logs, etc.) off individual holdings.
    func apply(to account: Account, in context: ModelContext) {
        // Snapshot before mutating so we can detect a manual balance
        // change at the end and log it as a transaction. For
        // investment accounts `account.balance` represents the liquid
        // cash component only — holdings live in their own table and
        // are deliberately excluded from this log (per CLAUDE.md, the
        // transactions log is for income/expense, not portfolio moves).
        let previousBalance = account.balance
        let previousCurrencyCode = account.currencyCode

        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.type = type
        account.balance = balance
        account.currencyCode = currencyCode
        account.lastUpdated = .now

        // Favourite is single-select: if this one is being promoted,
        // demote every other account first so the invariant holds.
        // We do this *before* setting the flag on `account` itself so
        // we don't accidentally clear it again in the same loop.
        if isFavorite {
            if let others = try? context.fetch(FetchDescriptor<Account>()) {
                for other in others where other.persistentModelID != account.persistentModelID {
                    if other.isFavorite { other.isFavorite = false }
                }
            }
        }
        account.isFavorite = isFavorite

        for existing in account.holdings {
            context.delete(existing)
        }

        if type == .investment {
            for hd in holdings {
                let holding = Holding(
                    symbol: hd.symbol.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: hd.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    quantity: hd.quantity,
                    marketValue: hd.marketValue,
                    currencyCode: hd.currencyCode,
                    lastUpdated: .now
                )
                holding.account = account
                context.insert(holding)
            }
        }

        // Manual balance edits leave a paper trail in the transactions
        // log so the user can scroll back and see "I bumped my current
        // account by ₪500 last Tuesday" even though nothing else
        // happened. Skipped when the currency code also changed in the
        // same edit — comparing decimals across currencies is
        // meaningless, so we don't fabricate a delta number for it.
        let balanceDelta = balance - previousBalance
        if balanceDelta != 0, currencyCode == previousCurrencyCode {
            let kind: TransactionKind = balanceDelta > 0 ? .income : .expense
            let manualEdit = Transaction(
                amount: abs(balanceDelta),
                kind: kind,
                date: .now,
                title: Transaction.manualBalanceEditTitle,
                note: "",
                currencyCode: account.currencyCode,
                balanceAfter: account.balance,
                category: nil,
                account: account
            )
            context.insert(manualEdit)
        }

        try? context.save()
    }
}

/// A draft holding inside an investment account, edited inline during
/// onboarding and turned into a real `Holding` row at commit time.
struct HoldingDraft: Identifiable, Hashable {
    let id: UUID
    var symbol: String
    var name: String
    var quantity: Decimal
    var marketValue: Decimal
    var currencyCode: String

    init(
        id: UUID = UUID(),
        symbol: String = "",
        name: String = "",
        quantity: Decimal = 0,
        marketValue: Decimal = 0,
        currencyCode: String = "ILS"
    ) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.quantity = quantity
        self.marketValue = marketValue
        self.currencyCode = currencyCode
    }
}

extension HoldingDraft {
    init(from holding: Holding) {
        self.init(
            symbol: holding.symbol,
            name: holding.name,
            quantity: holding.quantity,
            marketValue: holding.marketValue,
            currencyCode: holding.currencyCode
        )
    }
}

// MARK: - Budget drafts

/// A single income source line being entered during onboarding. The
/// user names each one freely (e.g. "משכורת", "עבודה צדדית") so the
/// dashboard can report them by name rather than as anonymous totals.
struct IncomeSourceDraft: Identifiable, Hashable {
    let id: UUID
    var name: String
    var plannedAmount: Decimal
    var currencyCode: String
    /// When this income lands — monthly (e.g. salary on the 10th), yearly
    /// (an annual bonus), or a one-off. Defaults to plain recurring-monthly
    /// so the common case needs no extra taps.
    var schedule: BudgetSchedule

    init(
        id: UUID = UUID(),
        name: String = "",
        plannedAmount: Decimal = 0,
        currencyCode: String = "ILS",
        schedule: BudgetSchedule = BudgetSchedule()
    ) {
        self.id = id
        self.name = name
        self.plannedAmount = plannedAmount
        self.currencyCode = currencyCode
        self.schedule = schedule
    }
}

extension IncomeSourceDraft {
    /// Seed a draft from a persisted `BudgetItem`. Used by the
    /// post-onboarding budget editor so the same income editor sheet
    /// can edit existing rows.
    init(from item: BudgetItem) {
        self.init(
            name: item.name,
            plannedAmount: item.plannedAmount,
            currencyCode: item.currencyCode,
            schedule: BudgetSchedule(from: item)
        )
    }

    /// Writes this draft back into a persisted income `BudgetItem`.
    /// Kind stays `.income`, category stays nil — income lines never
    /// carry a category. Frequency is always monthly for income; the
    /// schedule controls which months it lands in.
    func apply(to item: BudgetItem) {
        item.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        item.plannedAmount = plannedAmount
        item.kind = .income
        item.currencyCode = currencyCode
        item.frequencyKind = .monthly
        item.frequencyWeeks = 1
        item.category = nil
        schedule.apply(to: item)
    }
}

/// A single planned expense line. Tied to a `Category` (which carries
/// its own need/want nature), plus an optional free-text `note` (e.g.
/// "ספר" for a barber under the "טיפוח" category) and a frequency so
/// non-monthly cadences are first-class.
struct PlannedExpenseDraft: Identifiable, Hashable {
    let id: UUID
    /// Reference to the seeded Category. SwiftData @Model classes are
    /// Hashable by identity, so this works inside our Hashable struct.
    /// `nil` only briefly while a brand-new draft is being filled in —
    /// the editor sheet won't allow saving without one.
    var category: Category?
    var note: String
    /// Amount per occurrence (per visit for `everyXWeeks`, per month
    /// for `monthly`). Roll-up to monthly happens on the dashboard.
    var plannedAmount: Decimal
    var currencyCode: String
    var frequencyKind: BudgetFrequencyKind
    var frequencyWeeks: Int
    /// When this expense lands — every month (rent), every year (car test),
    /// or a single dated event (a gift). Defaults to recurring-monthly.
    var schedule: BudgetSchedule

    init(
        id: UUID = UUID(),
        category: Category? = nil,
        note: String = "",
        plannedAmount: Decimal = 0,
        currencyCode: String = "ILS",
        frequencyKind: BudgetFrequencyKind = .monthly,
        frequencyWeeks: Int = 3,
        schedule: BudgetSchedule = BudgetSchedule()
    ) {
        self.id = id
        self.category = category
        self.note = note
        self.plannedAmount = plannedAmount
        self.currencyCode = currencyCode
        self.frequencyKind = frequencyKind
        self.frequencyWeeks = frequencyWeeks
        self.schedule = schedule
    }
}

extension PlannedExpenseDraft {
    /// Seed a draft from a persisted expense `BudgetItem`. The note
    /// field on the model holds the optional free-text label (e.g.
    /// "ספר" under "טיפוח"), which lives in `BudgetItem.name`.
    init(from item: BudgetItem) {
        self.init(
            category: item.category,
            note: item.name,
            plannedAmount: item.plannedAmount,
            currencyCode: item.currencyCode,
            frequencyKind: item.frequencyKind,
            frequencyWeeks: max(item.frequencyWeeks, 1),
            schedule: BudgetSchedule(from: item)
        )
    }

    /// Writes this draft back into a persisted expense `BudgetItem`.
    /// Kind is forced to `.expense` so an income row that somehow
    /// reaches this editor is corrected, not double-classified.
    func apply(to item: BudgetItem) {
        item.name = note.trimmingCharacters(in: .whitespacesAndNewlines)
        item.plannedAmount = plannedAmount
        item.kind = .expense
        item.currencyCode = currencyCode
        item.frequencyKind = frequencyKind
        item.frequencyWeeks = max(frequencyWeeks, 1)
        item.category = category
        schedule.apply(to: item)
    }
}
