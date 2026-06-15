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
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var budgetItems: [BudgetItem]
    /// Sorted newest first so `fxSnapshots.first` is always the freshest
    /// cached snapshot (or nil if we've never successfully fetched).
    @Query(sort: \FXRateSnapshot.fetchedAt, order: .reverse) private var fxSnapshots: [FXRateSnapshot]

    @State private var selectedTab: HomeBottomBar.Tab = .home
    @State private var editingAccount: Account?
    /// Drives the "תנועה חדשה" sheet. Boolean rather than an item-based
    /// trigger because the sheet builds its own draft internally; we
    /// just need to know "is it open or closed".
    @State private var isAddingTransaction: Bool = false
    /// Drives the budget editor sheet. Boolean for the same reason as
    /// `isAddingTransaction` — the sheet sources its own data via
    /// `@Query` and doesn't need a per-presentation seed value.
    @State private var isEditingBudget: Bool = false

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
        .sheet(item: $editingAccount) { account in
            AccountEditorSheet(
                draft: AccountDraft(from: account),
                isNew: false,
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
                        // `withAnimation` wraps the SwiftData mutation
                        // so the @Query refire animates the row out
                        // (collapse + fade) instead of a hard cut.
                        // The cascade rule on `Account.holdings`
                        // takes care of nested deletes; transactions
                        // pointing at this account get their link
                        // nullified.
                        withAnimation {
                            modelContext.delete(account)
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
                    }
                )

                BudgetSummaryCard(
                    budgetItems: budgetItems,
                    preferredCurrencyCode: preferredCurrencyCode,
                    fxSnapshot: fxSnapshots.first,
                    onEdit: { isEditingBudget = true }
                )

                MonthlySummaryCard(
                    transactions: transactions,
                    preferredCurrencyCode: preferredCurrencyCode,
                    fxSnapshot: fxSnapshots.first
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
    }

    private var headerRow: some View {
        HStack(alignment: .top) {
            GreetingHeaderView(name: profiles.first?.name ?? "")
            #if DEBUG
            DebugResetButton()
            #endif
        }
    }

    private var preferredCurrencyCode: String {
        profiles.first?.preferredCurrencyCode ?? "ILS"
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
        .modelContainer(for: [UserProfile.self, Account.self, Holding.self, Category.self, Transaction.self, BudgetItem.self, Goal.self, FXRateSnapshot.self], inMemory: true)
}
