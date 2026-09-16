import SwiftUI
import SwiftData

/// The dashboard.
///
/// All visual decisions — colours, fonts, spacing, card shape — come
/// from `Theme`. Sections, top to bottom:
///   1. Greeting (with name; in DEBUG, a reset button next to it).
///   2. Assets — combined hero balance in the preferred currency +
///      per-account rows.
///   3. Budget — combined planned monthly income, needs, wants, net.
///   4. This month — combined actual income, expense, net.
///
/// Cross-currency totals use cached Frankfurter FX rates (see
/// `FXRatesService`). On first appearance we kick off a refresh if
/// the cached snapshot is stale or missing; the rest of the view
/// reads from the cache via `@Query`.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserProfile]
    // Live rows only — soft-deleted accounts/transactions sit in
    // "Recently Deleted" (see `TrashService`) until restored or purged,
    // so every dashboard total ignores them.
    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.name)
    private var accounts: [Account]
    @Query(filter: #Predicate<Transaction> { $0.deletedAt == nil }, sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    /// Soft-deleted accounts, surfaced only as a count so the assets card
    /// can offer a "Recently Deleted" entry when there's something to recover.
    @Query(filter: #Predicate<Account> { $0.deletedAt != nil })
    private var deletedAccounts: [Account]
    @Query private var budgetItems: [BudgetItem]
    /// XP / streak standing. A `@Query` rather than a one-off fetch so the
    /// dashboard card and the level-up toast both re-render the moment
    /// `ProgressService` writes — including when the write came from inside a
    /// sheet that's busy dismissing itself. Sorted oldest-first to match the
    /// row `ProgressService` resolves to.
    @Query(sort: \UserProgress.createdAt, order: .forward)
    private var progressRows: [UserProgress]
    /// Sorted newest first so `fxSnapshots.first` is always the freshest
    /// cached snapshot (or nil if we've never successfully fetched).
    @Query(sort: \FXRateSnapshot.fetchedAt, order: .reverse) private var fxSnapshots: [FXRateSnapshot]

    @State private var selectedTab: HomeBottomBar.Tab = .home
    /// The transactions list's filters, owned here rather than by the list.
    /// Switching tabs rebuilds the branch below, which used to wipe them — a
    /// glance at the dashboard shouldn't cost the user the filter they just
    /// set. Lives for the session; see `TransactionFilters`.
    @State private var transactionFilters = TransactionFilters()
    @State private var editingAccount: Account?
    /// Drives the "חשבון חדש" sheet from the assets card's add button.
    /// Boolean rather than item-based because the sheet seeds its own
    /// fresh draft — there's no existing account to hand it.
    @State private var isAddingAccount: Bool = false
    /// Drives the "תנועה חדשה" sheet. Boolean rather than an item-based
    /// trigger because the sheet builds its own draft internally; we
    /// just need to know "is it open or closed".
    @State private var isAddingTransaction: Bool = false
    /// Drives the budget editor sheet. Boolean for the same reason as
    /// `isAddingTransaction` — the sheet sources its own data via
    /// `@Query` and doesn't need a per-presentation seed value.
    @State private var isEditingBudget: Bool = false
    /// Drives the "Recently Deleted" sheet, opened from the assets card
    /// when there are soft-deleted accounts to recover.
    @State private var isShowingRecentlyDeleted: Bool = false
    /// The period the budget card shows: the card's segmented control picks
    /// the unit (month/year) and the surrounding carousel steps the anchor
    /// back and forward in time — same vocabulary as the Analytics roadmap.
    /// Lives here because HomeView builds the report.
    @State private var budgetPeriod: AnalyticsPeriod = .current()
    /// Drives the budget-overrun alert. Raised at most **once per calendar
    /// month** — the card's inline banner carries the warning from then on.
    @State private var overrunAlertPresented: Bool = false
    /// The month whose overrun has already been announced, as "2026-9".
    ///
    /// Persisted in `UserDefaults` rather than held in `@State`: a session
    /// latch still re-fired the alert on every cold launch, which is the
    /// nagging the user saw. Once told that *this* month is over budget,
    /// the user doesn't need telling again — but a new month re-arms it,
    /// so the next breach still gets its one alert. Device-local UI state,
    /// so it stays out of `UserProfile` (and out of a later iCloud sync).
    @AppStorage("acknowledgedOverrunMonth") private var acknowledgedOverrunMonth: String = ""

    /// The matured deposit currently being asked about, if any. Item-based so
    /// the sheet always has a deposit to talk about, and so dismissing clears
    /// the queue position in one place.
    @State private var depositAwaitingPayout: Account?
    /// Deposits the user said "לא עכשיו" to. Session-scoped on purpose: the
    /// reminder is meant to come back, just not immediately — a new launch
    /// asks again. (Contrast the overrun alert, which is latched for the whole
    /// month in `UserDefaults`; that one is a warning, this one is a task
    /// that still needs doing.)
    @State private var postponedDeposits: Set<PersistentIdentifier> = []
    /// The deposit paid out automatically this launch, surfaced as a quiet
    /// confirmation so money never moves without the user being told.
    @State private var autoPaidDeposit: Account?
    /// How many *other* deposits were paid out in the same pass. Rare (it
    /// takes two deposits maturing on the same day, both set to automatic)
    /// but the confirmation would otherwise report one transfer when several
    /// happened.
    @State private var autoPaidExtraCount: Int = 0

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            // The two tab branches share the outer chrome (background,
            // bottom bar, FAB, sheets). Picking inside the ZStack keeps
            // the safeAreaInset and overlay below from re-rendering on
            // every tab swap.
            Group {
                switch selectedTab {
                case .home:
                    dashboardScroll
                case .transactions:
                    NavigationStack {
                        TransactionsListView(filters: transactionFilters)
                    }
                case .analytics:
                    NavigationStack {
                        AnalyticsView()
                    }
                case .calendar:
                    NavigationStack {
                        BudgetCalendarView()
                    }
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
        }
        .safeAreaInset(edge: .bottom) {
            HomeBottomBar(selection: $selectedTab)
                .padding(.horizontal, Theme.Spacing.md)
                // The home button pops above the bar by half its
                // diameter — reserve that headroom in the inset so
                // the popped portion isn't clipped by the scroll
                // content above.
                .padding(.top, HomeBottomBar.homeButtonDiameter / 2)
                .padding(.bottom, Theme.Spacing.sm)
        }
        // The FAB hovers above the bottom bar in the visual right
        // corner. `.bottomLeading` is intentional: the app is RTL
        // Hebrew, so leading maps to the visual right edge — that's
        // the corner the user reaches with their thumb.
        .overlay(alignment: .bottomLeading) {
            FloatingAddButton {
                isAddingTransaction = true
            }
            // Lift the FAB high enough that it reads as a separate
            // floating element from the bottom bar — clearing both
            // the bar's height *and* the home button that pops out
            // of its notch, with a generous gap on top so they don't
            // visually touch. The figure lives on `HomeBottomBar` so the
            // scrolling screens can derive their bottom clearance from the
            // same number.
            .padding(.leading, Theme.Spacing.lg)
            .padding(.bottom, HomeBottomBar.floatingButtonBottomPadding)
        }
        // Level-ups are celebrated at the shell level, not on the dashboard:
        // the XP that triggered one was almost certainly earned in a sheet on
        // top of some other tab, and the user should see it wherever they are.
        // The toast clears the flag itself once it has finished animating out.
        .overlay(alignment: .top) {
            if let level = progressRows.first?.pendingLevelUpLevel {
                LevelUpToast(level: level) {
                    ProgressService.clearPendingLevelUp(in: modelContext)
                }
            }
        }
        .sheet(isPresented: $isAddingTransaction) {
            NewTransactionSheet()
        }
        .sheet(isPresented: $isEditingBudget) {
            BudgetEditorSheet()
        }
        .sheet(isPresented: $isShowingRecentlyDeleted) {
            RecentlyDeletedView()
        }
        .sheet(isPresented: $isAddingAccount) {
            AccountEditorSheet(
                // Seed the draft in the user's preferred currency, matching
                // the onboarding add button. Nothing is persisted yet, so
                // the currency picker stays editable (unlike the edit flow
                // below, which locks it on an already-saved account).
                draft: AccountDraft(currencyCode: preferredCurrencyCode),
                isNew: true,
                lockCurrency: false,
                // A brand-new deposit can already pick where it pays out.
                // Nothing to exclude — it isn't one of the saved accounts yet.
                payoutCandidates: payoutCandidates(),
                onSave: { draft in addAccount(draft) },
                onCancel: {}
            )
        }
        .sheet(item: $editingAccount) { account in
            AccountEditorSheet(
                draft: AccountDraft(from: account),
                isNew: false,
                // Dashboard edits target a persisted account, so the
                // currency picker is locked here — see AccountEditorSheet
                // for the reasoning. Onboarding leaves it on the default
                // (unlocked) since drafts haven't been committed yet.
                lockCurrency: true,
                // Every other live account is a possible payout target for a
                // deposit. Onboarding passes none — nothing is persisted yet.
                payoutCandidates: payoutCandidates(excluding: account),
                onSave: { updated in
                    updated.apply(to: account, in: modelContext)
                },
                onCancel: {}
            )
        }
        // Deep link from the home-screen widget: `oshrat://new-transaction`
        // opens the same sheet as the FAB. Handled here (not in
        // `OshRatApp`) because this view already owns the sheet's state.
        // If the user hasn't onboarded yet, `ContentView` never mounts
        // `HomeView`, so the URL is quietly ignored — correct, since
        // there's no account to log a transaction against.
        .onOpenURL { url in
            guard url.scheme == "oshrat", url.host() == "new-transaction" else { return }
            isAddingTransaction = true
        }
        // Refresh once per dashboard appearance. The service itself
        // gates on cache freshness, so this is cheap when the cache
        // is still warm.
        .task {
            await FXRatesService.refreshIfNeeded(in: modelContext)
        }
        // Sweep out anything that's sat in "Recently Deleted" past the
        // retention window. Cheap on a hand-entered ledger, so doing it on
        // appearance is plenty — there's no background scheduler in the MVP.
        .task {
            TrashService.purgeExpired(in: modelContext)
        }
    }

    /// Dashboard branch of the tab switch — the original home-screen
    /// scroll view, just lifted into its own property so the tab
    /// switch in `body` reads as a flat picker between two surfaces.
    private var dashboardScroll: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                headerRow

                AssetsSummaryCard(
                    accounts: accounts,
                    preferredCurrencyCode: preferredCurrencyCode,
                    fxSnapshot: fxSnapshots.first,
                    onEditAccount: { account in
                        editingAccount = account
                    },
                    onDeleteAccount: { account in
                        // Soft delete: the account is hidden (and drops out
                        // of every total) but kept for recovery from
                        // "Recently Deleted". `withAnimation` wraps the
                        // mutation so the @Query refire animates the row
                        // out instead of a hard cut. Its holdings and
                        // transactions stay attached for a later restore.
                        withAnimation {
                            TrashService.softDelete(account)
                            try? modelContext.save()
                        }
                    },
                    onToggleFavorite: { account in
                        // Enforce the "at most one favourite" rule here
                        // rather than in the card — the card only knows
                        // about the row it owns. Toggling off clears the
                        // flag without picking a replacement, since the
                        // sheet falls back to `accounts.first` anyway.
                        withAnimation {
                            let willBeFavorite = !account.isFavorite
                            if willBeFavorite {
                                for other in accounts where other.isFavorite && other !== account {
                                    other.isFavorite = false
                                }
                            }
                            account.isFavorite = willBeFavorite
                            try? modelContext.save()
                        }
                    },
                    onAddAccount: { isAddingAccount = true },
                    deletedAccountCount: deletedAccounts.count,
                    onShowRecentlyDeleted: { isShowingRecentlyDeleted = true }
                )

                // Sits under the assets card rather than above it: the
                // greeting mascot is pinned to the top of the assets card by
                // a negative inset, and net worth stays the first number on
                // the screen. Still above the fold now that the assets card
                // caps itself at three rows.
                LevelProgressCard(progress: progressRows.first)

                // Swipeable previous/next-period pager. Negative padding
                // cancels the VStack's gutter so the scroll view spans the
                // full screen and its clip stays clear of the card shadows;
                // the pager puts the same gutter back as content margins, so
                // the card itself lines up with the ones above.
                BudgetCardCarousel(
                    period: $budgetPeriod,
                    makeReport: { report(for: $0) },
                    onEdit: { isEditingBudget = true }
                )
                .padding(.horizontal, -Theme.Spacing.lg)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            // Only the bar's own clearance here, not the floating "+"'s. The
            // dashboard's last element is a card, not a control — nothing at
            // its bottom edge needs tapping — so letting the "+" hover over
            // that edge costs nothing and saves a chunk of dead space at the
            // end of the scroll. Screens that end in a *button* use
            // `floatingButtonClearance` instead.
            .padding(.bottom, HomeBottomBar.barClearance)
        }
        .scrollIndicators(.hidden)
        // Raise the overrun alert the moment the month goes over budget, and
        // then not again for that month. `initial: true` catches a breach
        // that happened while the app was closed (the @Query data is ready
        // synchronously); `acknowledgedOverrunMonth` is the latch.
        // Keyed to the *monthly* report on purpose: the alert warns about
        // this month's budget, so toggling the card to the year view must
        // neither trigger nor re-word it.
        .onChange(of: monthlyBudgetReport.hasOverrun, initial: true) { _, isOverBudget in
            guard isOverBudget, acknowledgedOverrunMonth != currentMonthKey else { return }
            overrunAlertPresented = true
            acknowledgedOverrunMonth = currentMonthKey
        }
        .alert(
            Text("חריגה מהתקציב"),
            isPresented: $overrunAlertPresented,
            presenting: monthlyBudgetReport.overrunSummary
        ) { _ in
            Button("הבנתי", role: .cancel) {}
            Button("לתקציב") { isEditingBudget = true }
        } message: { summary in
            Text(overrunMessage(summary))
        }
        // Deposits that have reached maturity. Checked on every dashboard
        // appearance rather than once at launch: a deposit can mature while
        // the app sits open overnight, and coming back to the dashboard is
        // the moment the user is looking at their money anyway.
        .task(id: maturedDepositIDs) {
            settleMaturedDeposits()
        }
        .sheet(item: $depositAwaitingPayout) { deposit in
            DepositMaturitySheet(
                deposit: deposit,
                candidates: payoutCandidates(excluding: deposit),
                fxSnapshot: fxSnapshots.first,
                onConfirm: { amount, target in
                    payOut(deposit, amount: amount, to: target)
                },
                onPostpone: {
                    postponedDeposits.insert(deposit.persistentModelID)
                }
            )
        }
        .alert(
            Text("הפיקדון נפדה"),
            isPresented: autoPaidAlertBinding,
            presenting: autoPaidDeposit
        ) { _ in
            Button("הבנתי", role: .cancel) {}
        } message: { deposit in
            Text(autoPayoutMessage(deposit))
        }
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            GreetingHeaderView(name: profiles.first?.name ?? "")
            #if DEBUG
            DebugResetButton()
            #endif
        }
    }

    /// Turns a freshly filled draft into a persisted `Account`.
    ///
    /// This mirrors the per-account loop in `OnboardingViewModel.commit`
    /// rather than reusing `AccountDraft.apply(to:in:)` on purpose: `apply`
    /// logs a "manual balance edit" transaction whenever the balance
    /// differs from the account's previous value, which for a brand-new
    /// account (previous balance 0) would fabricate a bogus transaction
    /// for the opening balance. Opening balances are the source of truth,
    /// not a logged movement — so we create the row directly here.
    private func addAccount(_ draft: AccountDraft) {
        withAnimation {
            // A new account may claim the single "favourite" slot. Clear
            // the flag off every existing account first so the invariant
            // (at most one favourite) holds — same rule as the toggle
            // handler above.
            if draft.isFavorite {
                for other in accounts where other.isFavorite {
                    other.isFavorite = false
                }
            }

            let account = Account(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: draft.type,
                balance: draft.balance,
                currencyCode: draft.currencyCode,
                lastUpdated: .now,
                isFavorite: draft.isFavorite
            )
            modelContext.insert(account)

            // Deposit terms, if this is a savings account. Mirrors the same
            // block in `OnboardingViewModel.commit` — but here the payout
            // target *can* be resolved, because every candidate is already
            // persisted by the time the dashboard offers them.
            if draft.type == .savings {
                account.interestRatePercent = draft.storedInterestRate
                account.depositStartDate = draft.depositStartDate
                account.maturityDate = draft.storedMaturityDate
                account.autoPayoutOnMaturity = draft.autoPayoutOnMaturity
                account.payoutAccount = draft.payoutAccountID.flatMap {
                    modelContext.model(for: $0) as? Account
                }
            }

            // Holdings only make sense on investment accounts. Setting the
            // inverse relationship keeps `Account.holdings` in sync without
            // appending by hand.
            if draft.type == .investment {
                for hd in draft.holdings {
                    let holding = Holding(
                        symbol: hd.symbol.trimmingCharacters(in: .whitespacesAndNewlines),
                        name: hd.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        quantity: hd.quantity,
                        marketValue: hd.marketValue,
                        currencyCode: hd.currencyCode,
                        lastUpdated: .now
                    )
                    holding.account = account
                    modelContext.insert(holding)
                }
            }

            try? modelContext.save()
        }
    }

    private var preferredCurrencyCode: String {
        profiles.first?.preferredCurrencyCode ?? "ILS"
    }

    // MARK: - Deposit maturity

    /// Identities of the deposits currently owed a payout. Used as the
    /// `.task(id:)` key so the settle pass re-runs when a deposit matures or
    /// one is dealt with, and *not* on every unrelated redraw.
    private var maturedDepositIDs: [PersistentIdentifier] {
        DepositPayoutService.depositsAwaitingPayout(in: accounts).map(\.persistentModelID)
    }

    /// Deal with every deposit that has come due: pay out the ones set to
    /// automatic, and queue the first of the rest for the prompt.
    ///
    /// Automatic payouts still need a target — a deposit set to "transfer
    /// automatically" whose payout account was never chosen (or was since
    /// deleted) has nowhere to send the money, so it falls through to the
    /// prompt rather than guessing an account on the user's behalf.
    private func settleMaturedDeposits() {
        let due = DepositPayoutService.depositsAwaitingPayout(in: accounts)
        guard !due.isEmpty else { return }

        var needsPrompt: [Account] = []
        for deposit in due {
            guard deposit.autoPayoutOnMaturity,
                  let target = deposit.payoutAccount,
                  target.deletedAt == nil,
                  DepositPayoutService.canPayOut(deposit, to: target, using: fxSnapshots.first)
            else {
                needsPrompt.append(deposit)
                continue
            }
            payOut(deposit, amount: DepositPayoutService.suggestedPayoutAmount(for: deposit), to: target)
            if autoPaidDeposit == nil {
                autoPaidDeposit = deposit
            } else {
                autoPaidExtraCount += 1
            }
        }

        // One at a time: clearing a backlog of prompts in a single stack of
        // sheets would be worse than being asked again on the next appearance.
        if depositAwaitingPayout == nil {
            depositAwaitingPayout = needsPrompt.first {
                !postponedDeposits.contains($0.persistentModelID)
            }
        }
    }

    /// Runs the payout and saves. `withAnimation` so the assets card's rows
    /// and totals move rather than jumping — money leaving one account and
    /// landing in another is exactly the kind of change worth seeing happen.
    private func payOut(_ deposit: Account, amount: Decimal, to target: Account) {
        withAnimation {
            DepositPayoutService.payOut(
                deposit,
                amount: amount,
                to: target,
                in: modelContext,
                using: fxSnapshots.first
            )
            try? modelContext.save()
        }
    }

    /// Accounts a deposit can pay into: live **עו״ש** accounts only.
    ///
    /// A matured deposit lands in a current account — that's what the bank
    /// actually does. Offering wallets, other deposits or investment accounts
    /// filled the picker with targets that made no sense (and a deposit paying
    /// into itself would be a no-op that zeroes nothing).
    ///
    /// The one exception is an account this deposit *already* points at: it
    /// stays in the list even if it isn't an עו״ש, so a deposit set up before
    /// this rule doesn't open with a blank picker and quietly lose its target.
    private func payoutCandidates(excluding deposit: Account? = nil) -> [Account] {
        let existingTarget = deposit?.payoutAccount?.persistentModelID
        return accounts.filter { account in
            guard account.persistentModelID != deposit?.persistentModelID else { return false }
            return account.type == .current || account.persistentModelID == existingTarget
        }
    }

    /// `.alert(presenting:)` wants a `Binding<Bool>`; bridge it through the
    /// optional deposit so dismissing clears it in one place. Same shape as
    /// the delete confirmation in `AssetsSummaryCard`.
    private var autoPaidAlertBinding: Binding<Bool> {
        Binding(
            get: { autoPaidDeposit != nil },
            set: {
                if !$0 {
                    autoPaidDeposit = nil
                    autoPaidExtraCount = 0
                }
            }
        )
    }

    private func autoPayoutMessage(_ deposit: Account) -> String {
        let name = deposit.name.isEmpty ? "הפיקדון" : deposit.name
        let target = deposit.payoutAccount?.name ?? ""
        var message = "\(name) הועבר אל \(target). ההעברה והריבית מופיעות ביומן התנועות."
        if autoPaidExtraCount > 0 {
            // `String(localized:)` so the count pluralises properly in Hebrew
            // (פיקדון אחד / שני פיקדונות / N פיקדונות) via the catalog.
            message += " " + String(localized: "נפדו גם \(autoPaidExtraCount) פיקדונות נוספים.")
        }
        return message
    }

    /// Identity of the month the alert latch is keyed to ("2026-9"). Changing
    /// month is what re-arms the alert, so the granularity has to match the
    /// report's scope exactly.
    private var currentMonthKey: String {
        let parts = Calendar.current.dateComponents([.year, .month], from: .now)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    /// Always *this month's* plan-vs-reality, backing the overrun alert —
    /// its semantics ("this month's budget was breached") must not follow
    /// the card as the user browses other periods or the year view. Cheap on
    /// a hand-entered ledger, so recomputing per render is fine.
    private var monthlyBudgetReport: BudgetVsActual {
        report(for: .current())
    }

    /// Plan-vs-reality for an arbitrary period (any month or year, past or
    /// future), rebuilt from the live `@Query` data. Feeds the carousel's
    /// centre card and its peeking neighbours.
    private func report(for period: AnalyticsPeriod) -> BudgetVsActual {
        BudgetVsActual(
            budgetItems: budgetItems,
            transactions: transactions,
            preferredCurrency: preferredCurrencyCode,
            fxSnapshot: fxSnapshots.first,
            scope: period.scope,
            now: period.anchor
        )
    }

    /// Multi-line Hebrew breakdown for the overrun alert: each budgeted
    /// category that ran over, plus a total line when the whole expense plan
    /// was blown.
    private func overrunMessage(_ summary: OverrunSummary) -> String {
        let code = preferredCurrencyCode
        var lines = summary.lines.map { line in
            "\(line.bucket.hebrewLabel): \(line.actual.formattedCurrency(code)) מתוך \(line.planned.formattedCurrency(code)) — חריגה של \(line.overAmount.formattedCurrency(code))"
        }
        if summary.isTotalOver {
            lines.append(
                "סך ההוצאות: \(summary.totalActual.formattedCurrency(code)) מתוך \(summary.totalPlanned.formattedCurrency(code)) — חריגה של \(summary.totalOverAmount.formattedCurrency(code))"
            )
        }
        return lines.joined(separator: "\n")
    }
}

/// Circular floating "+" used to open the new-transaction sheet.
///
/// Tap is two-stage so the press registers as motion: the button springs
/// in for a moment (scale ~0.85 + tiny rotation on the symbol) then
/// rebounds before firing `action`. The delay is small enough that the
/// sheet still feels instant.
private struct FloatingAddButton: View {
    let action: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isPressed = false
                }
                action()
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isPressed ? 45 : 0))
                .frame(
                    width: HomeBottomBar.floatingButtonDiameter,
                    height: HomeBottomBar.floatingButtonDiameter
                )
                .background(
                    Circle().fill(Theme.Colors.accent)
                )
                .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 4)
                .scaleEffect(isPressed ? 0.86 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("תנועה חדשה"))
    }
}

#if DEBUG
/// Debug-only button that wipes every SwiftData row and re-seeds the
/// default categories. Lets the developer re-run the onboarding flow
/// repeatedly in the Simulator without uninstalling the app. Compiled
/// out of Release builds entirely.
private struct DebugResetButton: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirming: Bool = false

    var body: some View {
        Button {
            isConfirming = true
        } label: {
            Image(systemName: "arrow.counterclockwise.circle")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(Theme.Spacing.sm)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("איפוס נתונים (פיתוח בלבד)"))
        .confirmationDialog(
            Text("איפוס כל הנתונים?"),
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("איפוס", role: .destructive) {
                resetAll()
            }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("ימחק את הפרופיל, החשבונות, הנכסים, התקציב והעסקאות. הקטגוריות יוטענו מחדש כברירת מחדל. שימושי בעיקר כדי להריץ שוב את ההתחלה במהלך פיתוח.")
        }
    }

    private func resetAll() {
        // We *used* to call `modelContext.delete(model: T.self)` here
        // for every type — that's a batch delete, and SwiftData doesn't
        // always notify `@Query` observers when it runs. The symptom
        // was that the transactions list (and other dashboard views)
        // still showed the rows from before the reset until a cold
        // relaunch. Fetching the rows and deleting them one by one is
        // slower in theory but reliably fires the change-tracking
        // that @Query listens to, so views refresh immediately.
        do {
            try deleteAll(of: Transaction.self)
            try deleteAll(of: BudgetItem.self)
            try deleteAll(of: Goal.self)
            try deleteAll(of: Holding.self)
            try deleteAll(of: Account.self)
            try deleteAll(of: Category.self)
            try deleteAll(of: UserProfile.self)
            try deleteAll(of: FXRateSnapshot.self)
            // XP too, or a reset would drop the user back into onboarding
            // still carrying their level — and with the setup milestones
            // already marked paid, they'd never be awarded again.
            try deleteAll(of: UserProgress.self)
            try modelContext.save()
        } catch {
            print("Reset failed: \(error)")
        }
        for category in SeedData.defaultCategories() {
            modelContext.insert(category)
        }
        try? modelContext.save()
    }

    /// Fetch-then-delete loop. Issues one delete per row so SwiftData
    /// fires its per-object change notifications — the batch-delete
    /// variant misses these, leaving any `@Query` observers stale.
    private func deleteAll<T: PersistentModel>(of type: T.Type) throws {
        let rows = try modelContext.fetch(FetchDescriptor<T>())
        for row in rows {
            modelContext.delete(row)
        }
    }
}
#endif

#Preview {
    HomeView()
        .modelContainer(for: [UserProfile.self, Account.self, Holding.self, Category.self, Transaction.self, TransactionAttachment.self, BudgetItem.self, Goal.self, FXRateSnapshot.self], inMemory: true)
}
