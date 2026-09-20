import Foundation
import SwiftData

#if DEBUG

// MARK: - Scenarios

/// A ready-made life the app can be filled with, so a data-driven screen can be
/// looked at without hand-entering a year of transactions first.
///
/// Each one is a different *shape* of finances, chosen to exercise a different
/// corner of the app: a simple one-account ledger, a two-income household with
/// foreign currency and annual bills, a saver with a whole shelf of deposits
/// (including one owed a payout and a replenishable ladder), and an irregular
/// freelance income with securities trades.
///
/// DEBUG-only, like everything in this file — none of it is compiled into a
/// release build.
enum DemoScenario: String, CaseIterable, Identifiable {
    case youngProfessional
    case family
    case saver
    case freelancer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .youngProfessional: return "בתחילת הדרך"
        case .family:            return "משפחה עם ילדים"
        case .saver:             return "חוסך עם פיקדונות"
        case .freelancer:        return "עצמאי עם הכנסה משתנה"
        }
    }

    /// One line on what this scenario is *for* — which screens it lights up.
    var summary: String {
        switch self {
        case .youngProfessional:
            return "חשבון אחד, ארנק דיגיטלי וחיסכון פתוח. תקציב פשוט, בלי פיקדונות."
        case .family:
            return "שתי הכנסות, חשבון דולרי, הוצאות שנתיות (ביטוח, חופשה) ותוכנית חיסכון לילדים שמקבלת הפקדה כל חודש."
        case .saver:
            return "ארבעה פיקדונות: אחד שכבר הגיע לפדיון ומחכה, אחד שרץ, ותוכנית חיסכון עם הפקדה חודשית שמייצרת עשרות תת-הפקדות."
        case .freelancer:
            return "הכנסה לא סדירה מחשבוניות, קניות ומכירות ני״ע, ופיקדון קצר עם פדיון אוטומטי."
        }
    }

    /// How much history the scenario generates by default. Longer histories
    /// make the Analytics roadmap and the budget carousel worth looking at;
    /// shorter ones keep a deploy quick.
    var defaultMonths: Int {
        switch self {
        case .youngProfessional: return 12
        case .family:            return 24
        case .saver:             return 36
        case .freelancer:        return 18
        }
    }

    /// Fixed seed per scenario, so the same scenario always produces the same
    /// ledger — a bug found in demo data can be reproduced exactly.
    fileprivate var seed: UInt64 {
        switch self {
        case .youngProfessional: return 0x0517_1A
        case .family:            return 0x0517_2B
        case .saver:             return 0x0517_3C
        case .freelancer:        return 0x0517_4D
        }
    }
}

/// What's currently in the store, for the admin panel's "before you overwrite
/// it" summary.
struct DemoStoreSummary {
    var hasProfile = false
    var accounts = 0
    var transactions = 0
    var budgetItems = 0
    var goals = 0
    var deposits = 0
    var depositTranches = 0

    var isEmpty: Bool {
        !hasProfile && accounts == 0 && transactions == 0 && budgetItems == 0 && goals == 0
    }
}

// MARK: - Service

/// Fills (or empties) the store for development.
///
/// A `@MainActor enum` with no state of its own, like the other services here —
/// the SwiftData store is the state.
///
/// **Deploying always wipes first.** A scenario is a whole life, not a top-up:
/// merging one into leftover data would produce balances that match nothing and
/// make every screen a lie. "Start from scratch" is the same wipe without the
/// seeding, which drops the app back into onboarding (`ContentView` routes on
/// the presence of a `UserProfile`).
@MainActor
enum DemoDataService {

    // MARK: Deploy

    /// Wipe the store and fill it with `scenario`.
    ///
    /// - Parameter monthsOverride: history length in months, or `nil` for the
    ///   scenario's own default.
    static func deploy(
        _ scenario: DemoScenario,
        monthsOverride: Int? = nil,
        in context: ModelContext,
        now: Date = .now
    ) {
        let months = max(1, monthsOverride ?? scenario.defaultMonths)
        wipe(in: context, reseedCategories: true)

        var generator = SeededGenerator(seed: scenario.seed)
        let plan = DemoScenarioLibrary.blueprint(for: scenario)
        let calendar = Calendar.current

        // 1. Who the user is.
        let profile = UserProfile(
            name: plan.profileName,
            profession: plan.profession,
            goalsText: plan.goalsText,
            preferredCurrencyCode: "ILS"
        )
        context.insert(profile)

        // 2. Accounts, then a second pass for the payout links (a deposit can
        //    point at an account created after it).
        var accountsByKey: [String: Account] = [:]
        for spec in plan.accounts {
            let account = Account(
                name: spec.name,
                type: spec.type,
                balance: spec.openingBalance,
                currencyCode: spec.currency,
                lastUpdated: now,
                isFavorite: spec.isFavorite && spec.type.allowsFavorite
            )
            if let deposit = spec.deposit {
                let start = calendar.date(byAdding: .month, value: -deposit.startMonthsAgo, to: now) ?? now
                account.depositKind = deposit.kind
                account.interestRatePercent = deposit.ratePercent
                account.depositStartDate = start
                account.maturityDate = calendar.date(byAdding: .month, value: deposit.termMonths, to: start)
                account.autoPayoutOnMaturity = deposit.autoPayout
            }
            context.insert(account)
            accountsByKey[spec.key] = account
        }
        for spec in plan.accounts {
            guard let targetKey = spec.deposit?.payoutAccountKey,
                  let deposit = accountsByKey[spec.key],
                  let target = accountsByKey[targetKey]
            else { continue }
            deposit.payoutAccount = target
        }

        // 3. The budget, mirroring the recurring rows the ledger will produce —
        //    planned-vs-actual is only interesting when both sides exist.
        let categories = categoriesByName(in: context)
        for spec in plan.incomes {
            let item = BudgetItem(
                name: spec.title,
                plannedAmount: spec.amount,
                kind: .income,
                recurrenceUnit: .month,
                scheduleKind: .recurringMonthly,
                scheduleDay: spec.day
            )
            context.insert(item)
        }
        for spec in plan.expenses {
            let item = BudgetItem(
                name: spec.title,
                plannedAmount: spec.amount,
                kind: .expense,
                recurrenceUnit: .month,
                scheduleKind: .recurringMonthly,
                scheduleDay: spec.day,
                category: spec.categoryName.flatMap { categories[$0] }
            )
            context.insert(item)
        }
        for spec in plan.annual {
            let item = BudgetItem(
                name: spec.title,
                plannedAmount: spec.amount,
                kind: .expense,
                recurrenceUnit: .year,
                scheduleKind: .recurringYearly,
                scheduleDay: spec.day,
                scheduleMonth: spec.month,
                category: categories[spec.categoryName]
            )
            context.insert(item)
        }
        // A planned line per random-spending bucket too, at roughly what the
        // bucket averages, so the budget card has something to compare against.
        for spec in plan.randomSpends {
            let item = BudgetItem(
                name: spec.plannedLabel,
                plannedAmount: spec.plannedMonthlyAmount,
                kind: .expense,
                recurrenceUnit: .month,
                scheduleKind: .recurringMonthly,
                category: categories[spec.categoryName]
            )
            context.insert(item)
        }

        // Irregular income (the freelancer's invoices) plans as one monthly
        // line, since that's the only shape the budget can express.
        if let invoices = DemoScenarioLibrary.invoices(for: scenario) {
            let item = BudgetItem(
                name: invoices.plannedLabel,
                plannedAmount: invoices.plannedMonthlyAmount,
                kind: .income,
                recurrenceUnit: .month,
                scheduleKind: .recurringMonthly
            )
            context.insert(item)
        }

        // 4. Goals.
        for spec in plan.goals {
            let goal = Goal(
                title: spec.title,
                targetAmount: spec.target,
                savedAmount: spec.saved,
                targetDate: spec.monthsAhead.flatMap { calendar.date(byAdding: .month, value: $0, to: now) },
                note: spec.note
            )
            context.insert(goal)
        }

        // 5. The ledger, in three steps: plan the rows, keep the wallets
        //    solvent, then back-solve the opening balances so the history adds
        //    up to the balances the dashboard is meant to show.
        let plannedRows = plannedRows(
            plan: plan,
            invoices: DemoScenarioLibrary.invoices(for: scenario),
            months: months,
            now: now,
            calendar: calendar,
            generator: &generator
        )
        let rows = withWalletTopUps(plannedRows, plan: plan)
        let deltas = netDeltas(rows)
        for spec in plan.accounts {
            guard let target = spec.targetClosingBalance, let account = accountsByKey[spec.key] else { continue }
            account.balance = target - (deltas[spec.key] ?? 0)
        }
        apply(rows, accountsByKey: accountsByKey, categories: categories, in: context)

        // 6. Cached FX, so a foreign-currency account rolls into the hero total
        //    without waiting on the network (and without a live fetch changing
        //    the numbers under a screenshot). Rough ECB-ish rates, EUR-based
        //    like the real snapshots.
        context.insert(
            FXRateSnapshot(
                base: "EUR",
                fetchedAt: now,
                rates: ["ILS": 3.95, "USD": 1.08, "EUR": 1.0, "GBP": 0.85]
            )
        )

        // 7. XP, so the level card isn't sitting at zero on a store that
        //    supposedly holds two years of logging. Written straight onto the
        //    row rather than replayed through `ProgressService` — the daily cap
        //    would swallow a backfill, and the level derives from the total
        //    anyway (`XPRules`).
        let progress = ProgressService.progress(in: context)
        progress.totalXP = plan.totalXP
        progress.currentStreak = plan.streak
        progress.longestStreak = plan.streak + 4
        progress.lastActivityDate = now
        progress.pendingLevelUpLevel = nil

        try? context.save()
    }

    // MARK: Wipe

    /// Get the app off any screen that is holding model objects, so the wipe
    /// below can't pull them out from under it.
    ///
    /// **Why this is needed.** `modelContext.delete` detaches an object
    /// immediately, but SwiftUI keeps the outgoing views alive for one more
    /// pass to animate them away — and the dashboard's account rows read
    /// `account.type` while they do. That traps with "This backing data was
    /// detached from a context", the same class of crash `RecentlyDeletedView`
    /// avoids by rendering from value snapshots (see CLAUDE.md).
    ///
    /// Deleting the `UserProfile` first is what gets us out: `ContentView`
    /// routes on the presence of a profile, so the dashboard is replaced by the
    /// onboarding screen — which holds no accounts — and by the time the rest
    /// of the rows go, nothing is reading them. Profiles are safe to delete
    /// while mounted because nothing renders them in a `ForEach`; the account
    /// rows were the hazard.
    ///
    /// The wait is a wait rather than a signal because SwiftUI offers no
    /// "teardown finished" callback. 150 ms is many times a render pass, and
    /// this is DEBUG-only tooling, so the bluntness is affordable.
    static func prepareForDestructiveWork(in context: ModelContext) async {
        deleteAll(UserProfile.self, in: context)
        try? context.save()
        await nextRunLoopTurn()
        try? await Task.sleep(for: .milliseconds(150))
        await nextRunLoopTurn()
    }

    private static func nextRunLoopTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// Delete every row. With `reseedCategories` the Hebrew starter categories
    /// go back in, which is what you want for "start from scratch" — onboarding
    /// expects them to exist.
    ///
    /// **Call `prepareForDestructiveWork` first from anywhere with a live UI.**
    /// This is only safe to call directly before any window exists (the launch
    /// arguments in `OshRatApp`).
    ///
    /// Rows are fetched and deleted one at a time rather than batch-deleted:
    /// SwiftData's batch delete doesn't reliably notify `@Query` observers, so
    /// the dashboard would keep showing the old ledger until a cold relaunch.
    static func wipe(in context: ModelContext, reseedCategories: Bool = true) {
        // Attachments and tranches first: they hang off rows deleted below, and
        // clearing them explicitly keeps the cascade from doing it mid-pass
        // while a view might still be reading.
        // The profile first: it's the row that decides whether the dashboard
        // is on screen at all (see `prepareForDestructiveWork`).
        deleteAll(UserProfile.self, in: context)
        deleteAll(TransactionAttachment.self, in: context)
        deleteAll(DepositTranche.self, in: context)
        deleteAll(Transaction.self, in: context)
        deleteAll(BudgetItem.self, in: context)
        deleteAll(Goal.self, in: context)
        deleteAll(Holding.self, in: context)
        deleteAll(Account.self, in: context)
        deleteAll(Category.self, in: context)
        deleteAll(FXRateSnapshot.self, in: context)
        // XP too — otherwise the user lands back in onboarding still carrying
        // their level, with the setup milestones already marked as paid.
        deleteAll(UserProgress.self, in: context)
        try? context.save()

        if reseedCategories {
            for category in SeedData.defaultCategories() {
                context.insert(category)
            }
            try? context.save()
        }
    }

    // MARK: Summary

    static func summary(in context: ModelContext) -> DemoStoreSummary {
        var summary = DemoStoreSummary()
        summary.hasProfile = !((try? context.fetch(FetchDescriptor<UserProfile>())) ?? []).isEmpty
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        summary.accounts = accounts.count
        summary.deposits = accounts.filter(\.isDeposit).count
        summary.transactions = count(Transaction.self, in: context)
        summary.budgetItems = count(BudgetItem.self, in: context)
        summary.goals = count(Goal.self, in: context)
        summary.depositTranches = count(DepositTranche.self, in: context)
        return summary
    }

    // MARK: - Ledger generation

    /// One transaction to be written, resolved down to plain values. Built for
    /// the whole history first and then applied in date order, because running
    /// balances (and the `balanceAfter` snapshots the list shows) only make
    /// sense if the rows land chronologically.
    private struct PlannedRow {
        var date: Date
        var accountKey: String
        var kind: TransactionKind
        var title: String
        var amount: Decimal
        var categoryName: String?
        /// Set for a transfer — the account credited, in which case `kind` is
        /// ignored (a transfer is marked by its destination amount).
        var destinationKey: String?
    }

    private static func plannedRows(
        plan: DemoBlueprint,
        invoices: DemoRandomIncomeSpec?,
        months: Int,
        now: Date,
        calendar: Calendar,
        generator: inout SeededGenerator
    ) -> [PlannedRow] {
        var rows: [PlannedRow] = []
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        // Walk oldest month → this month. `months - 1` back, so `months` is the
        // count of months touched including the current (partial) one.
        for offset in stride(from: months - 1, through: 0, by: -1) {
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart) else { continue }
            let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30

            func date(day: Int) -> Date? {
                let clamped = min(max(day, 1), daysInMonth)
                return calendar.date(byAdding: .day, value: clamped - 1, to: monthStart)
            }

            for spec in plan.incomes {
                guard let day = date(day: spec.day), day <= now else { continue }
                rows.append(
                    PlannedRow(
                        date: day,
                        accountKey: spec.accountKey,
                        kind: .income,
                        title: spec.title,
                        amount: jittered(spec.amount, percent: spec.jitter, using: &generator),
                        categoryName: spec.categoryName
                    )
                )
            }

            for spec in plan.expenses {
                guard let day = date(day: spec.day), day <= now else { continue }
                rows.append(
                    PlannedRow(
                        date: day,
                        accountKey: spec.accountKey,
                        kind: .expense,
                        title: spec.title,
                        amount: jittered(spec.amount, percent: spec.jitter, using: &generator),
                        categoryName: spec.categoryName
                    )
                )
            }

            // Annual bills land in their own month only.
            let month = calendar.component(.month, from: monthStart)
            for spec in plan.annual where spec.month == month {
                guard let day = date(day: spec.day), day <= now else { continue }
                rows.append(
                    PlannedRow(
                        date: day,
                        accountKey: spec.accountKey,
                        kind: .expense,
                        title: spec.title,
                        amount: spec.amount,
                        categoryName: spec.categoryName
                    )
                )
            }

            // Discretionary spending: a different count and spread every month,
            // which is what makes month-over-month comparisons and the
            // "records" station show anything at all.
            for spec in plan.randomSpends {
                let count = Int.random(in: spec.countRange, using: &generator)
                for _ in 0..<count {
                    guard let day = date(day: Int.random(in: 1...daysInMonth, using: &generator)), day <= now else { continue }
                    rows.append(
                        PlannedRow(
                            date: day,
                            accountKey: spec.accountKey,
                            kind: .expense,
                            title: spec.titles.randomElement(using: &generator) ?? spec.plannedLabel,
                            amount: Decimal(Int.random(in: spec.amountRange, using: &generator)),
                            categoryName: spec.categoryName
                        )
                    )
                }
            }

            // Invoices: a handful a month, never the same size twice.
            if let invoices {
                let count = Int.random(in: invoices.countRange, using: &generator)
                for _ in 0..<count {
                    guard let day = date(day: Int.random(in: 1...daysInMonth, using: &generator)), day <= now else { continue }
                    rows.append(
                        PlannedRow(
                            date: day,
                            accountKey: invoices.accountKey,
                            kind: .income,
                            title: invoices.titles.randomElement(using: &generator) ?? invoices.plannedLabel,
                            amount: Decimal(Int.random(in: invoices.amountRange, using: &generator)),
                            categoryName: invoices.categoryName
                        )
                    )
                }
            }

            // Money moved into savings. On a replenishable deposit each of
            // these opens a sub-deposit of its own — which is the whole point
            // of having this scenario.
            for spec in plan.transfers {
                guard let day = date(day: spec.day), day <= now else { continue }
                guard offset < spec.months else { continue }
                rows.append(
                    PlannedRow(
                        date: day,
                        accountKey: spec.fromKey,
                        kind: .expense,
                        title: spec.title,
                        amount: spec.amount,
                        categoryName: nil,
                        destinationKey: spec.toKey
                    )
                )
            }
        }

        return rows.sorted { $0.date < $1.date }
    }

    /// Keep a wallet solvent the way a person does: when the next thing it pays
    /// for is more than it holds, money moves in from the primary account first.
    ///
    /// Without this a wallet only ever pays out — every scenario charges coffee
    /// and deliveries to it — and ends the history tens of thousands in the red,
    /// which makes the assets card look broken rather than lived-in.
    private static func withWalletTopUps(_ rows: [PlannedRow], plan: DemoBlueprint) -> [PlannedRow] {
        var walletBalances: [String: Decimal] = [:]
        for spec in plan.accounts where spec.topUpWhenEmpty {
            walletBalances[spec.key] = spec.openingBalance
        }
        guard !walletBalances.isEmpty else { return rows }

        var result: [PlannedRow] = []
        result.reserveCapacity(rows.count)
        for row in rows {
            guard row.destinationKey == nil,
                  let balance = walletBalances[row.accountKey]
            else {
                // A transfer *into* the wallet still credits it.
                if let destination = row.destinationKey, let credited = walletBalances[destination] {
                    walletBalances[destination] = credited + row.amount
                }
                result.append(row)
                continue
            }

            var running = balance + (row.kind == .income ? row.amount : 0)
            if row.kind == .expense, running < row.amount {
                // Top up in round hundreds with a little headroom, so the
                // wallet doesn't need refilling again the same afternoon.
                let shortfall = row.amount - running + 200
                let topUp = roundedUpToHundreds(shortfall)
                result.append(
                    PlannedRow(
                        date: row.date,
                        accountKey: plan.primaryAccountKey,
                        kind: .expense,
                        title: "טעינת הארנק",
                        amount: topUp,
                        categoryName: nil,
                        destinationKey: row.accountKey
                    )
                )
                running += topUp
            }
            walletBalances[row.accountKey] = running - (row.kind == .expense ? row.amount : 0)
            result.append(row)
        }
        return result
    }

    /// What each account ends up net of the whole history. Lets a scenario name
    /// the balance it wants to *end* on and have the opening derived from it —
    /// otherwise the two are typed independently and a year of salary quietly
    /// inflates the dashboard into six figures.
    private static func netDeltas(_ rows: [PlannedRow]) -> [String: Decimal] {
        var deltas: [String: Decimal] = [:]
        for row in rows {
            if let destination = row.destinationKey {
                deltas[row.accountKey, default: 0] -= row.amount
                deltas[destination, default: 0] += row.amount
            } else {
                deltas[row.accountKey, default: 0] += row.kind == .income ? row.amount : -row.amount
            }
        }
        return deltas
    }

    private static func roundedUpToHundreds(_ value: Decimal) -> Decimal {
        var input = value / 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .up)
        return rounded * 100
    }

    /// Write the rows in date order, rolling each account's balance as we go so
    /// the stored `balanceAfter` snapshots match what the user would have seen.
    private static func apply(
        _ rows: [PlannedRow],
        accountsByKey: [String: Account],
        categories: [String: Category],
        in context: ModelContext
    ) {
        for row in rows {
            guard let account = accountsByKey[row.accountKey] else { continue }

            if let destinationKey = row.destinationKey, let destination = accountsByKey[destinationKey] {
                account.balance -= row.amount
                destination.balance += row.amount
                let transfer = Transaction(
                    amount: row.amount,
                    date: row.date,
                    title: row.title,
                    currencyCode: account.currencyCode,
                    balanceAfter: account.balance,
                    account: account,
                    destinationAccount: destination,
                    destinationAmount: row.amount,
                    destinationBalanceAfter: destination.balance
                )
                context.insert(transfer)
                // Same call the transfer sheet makes, so a demo deposit ladder
                // is built exactly the way a real one is.
                DepositLadderService.registerFunding(for: transfer, in: context)
                continue
            }

            account.balance += row.kind == .income ? row.amount : -row.amount
            let transaction = Transaction(
                amount: row.amount,
                kind: row.kind,
                date: row.date,
                title: row.title,
                currencyCode: account.currencyCode,
                balanceAfter: account.balance,
                category: row.categoryName.flatMap { categories[$0] },
                account: account
            )
            context.insert(transaction)
        }
    }

    // MARK: - Helpers

    private static func categoriesByName(in context: ModelContext) -> [String: Category] {
        let rows = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        // Expense categories win a name clash (e.g. "מתנות" exists on both
        // sides): every random-spend bucket here is an expense.
        return rows.reduce(into: [:]) { result, category in
            if result[category.name] == nil || category.kind == .expense {
                result[category.name] = category
            }
        }
    }

    /// Nudge an amount by up to ±`percent`, so a salary isn't the same figure to
    /// the shekel for two years and the insights card has something to notice.
    private static func jittered(_ amount: Decimal, percent: Int, using generator: inout SeededGenerator) -> Decimal {
        guard percent > 0 else { return amount }
        let swing = Int.random(in: -percent...percent, using: &generator)
        return amount + (amount * Decimal(swing) / 100)
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        guard let rows = try? context.fetch(FetchDescriptor<T>()) else { return }
        for row in rows {
            context.delete(row)
        }
    }

    private static func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? 0
    }
}

// MARK: - Deterministic randomness

/// SplitMix64, so a scenario's ledger is identical on every deploy. The system
/// generator would give a different store each time, which makes "it looked
/// wrong on my machine" impossible to chase.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#endif
