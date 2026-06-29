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
    /// Sorted newest first so `fxSnapshots.first` is always the freshest
    /// cached snapshot (or nil if we've never successfully fetched).
    @Query(sort: \FXRateSnapshot.fetchedAt, order: .reverse) private var fxSnapshots: [FXRateSnapshot]

    @State private var selectedTab: HomeBottomBar.Tab = .home
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
    /// Drives the budget-overrun alert. Auto-raised at most **once per app
    /// session** (the inline banner on the card carries the warning the rest
    /// of the time) — `hasShownOverrunAlert` is the latch. Both live on the
    /// long-lived `HomeView` so they survive tab switches.
    @State private var overrunAlertPresented: Bool = false
    @State private var hasShownOverrunAlert: Bool = false

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
                        TransactionsListView()
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
            // visually touch.
            .padding(.leading, Theme.Spacing.lg)
            .padding(.bottom, HomeBottomBar.barHeight + HomeBottomBar.homeButtonDiameter / 20 + Theme.Spacing.lg)
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
                onSave: { updated in
                    updated.apply(to: account, in: modelContext)
                },
                onCancel: {}
            )
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

                BudgetVsActualCard(
                    report: budgetReport,
                    onEdit: { isEditingBudget = true }
                )
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            // Reserve enough room for the FAB hovering above the bar
            // plus the home button that pops out of the notch — so
            // the bottom card never ends up under either of them.
            .padding(.bottom, HomeBottomBar.barHeight + HomeBottomBar.homeButtonDiameter + Theme.Spacing.lg)
        }
        .scrollIndicators(.hidden)
        // Raise the overrun alert once per session. `initial: true` checks on
        // first appearance too (the @Query data is ready synchronously); the
        // latch keeps it from re-firing as the user moves around the app.
        .onChange(of: budgetReport.hasOverrun, initial: true) { _, isOverBudget in
            if isOverBudget, !hasShownOverrunAlert {
                overrunAlertPresented = true
                hasShownOverrunAlert = true
            }
        }
        .alert(
            Text("חריגה מהתקציב"),
            isPresented: $overrunAlertPresented,
            presenting: budgetReport.overrunSummary
        ) { _ in
            Button("הבנתי", role: .cancel) {}
            Button("לתקציב") { isEditingBudget = true }
        } message: { summary in
            Text(overrunMessage(summary))
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

    /// This month's plan-vs-reality, rebuilt from the live `@Query` data.
    /// Cheap on a hand-entered ledger, so recomputing per render is fine; it
    /// feeds both the merged card and the overrun alert from one source.
    private var budgetReport: BudgetVsActual {
        BudgetVsActual(
            budgetItems: budgetItems,
            transactions: transactions,
            preferredCurrency: preferredCurrencyCode,
            fxSnapshot: fxSnapshots.first
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
                .frame(width: 60, height: 60)
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
