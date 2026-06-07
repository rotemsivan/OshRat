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

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    headerRow

                    AssetsSummaryCard(
                        accounts: accounts,
                        preferredCurrencyCode: preferredCurrencyCode,
                        fxSnapshot: fxSnapshots.first,
                        onEditAccount: { account in
                            editingAccount = account
                        }
                    )

                    BudgetSummaryCard(
                        budgetItems: budgetItems,
                        preferredCurrencyCode: preferredCurrencyCode,
                        fxSnapshot: fxSnapshots.first
                    )

                    MonthlySummaryCard(
                        transactions: transactions,
                        preferredCurrencyCode: preferredCurrencyCode,
                        fxSnapshot: fxSnapshots.first
                    )
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            HomeBottomBar(selection: $selectedTab)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
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
        do {
            try modelContext.delete(model: UserProfile.self)
            try modelContext.delete(model: Account.self)
            try modelContext.delete(model: Holding.self)
            try modelContext.delete(model: Transaction.self)
            try modelContext.delete(model: BudgetItem.self)
            try modelContext.delete(model: Goal.self)
            try modelContext.delete(model: Category.self)
            try modelContext.delete(model: FXRateSnapshot.self)
            try modelContext.save()
        } catch {
            print("Reset failed: \(error)")
        }
        for category in SeedData.defaultCategories() {
            modelContext.insert(category)
        }
        try? modelContext.save()
    }
}
#endif

#Preview {
    HomeView()
        .modelContainer(for: [UserProfile.self, Account.self, Holding.self, Category.self, Transaction.self, BudgetItem.self, Goal.self, FXRateSnapshot.self], inMemory: true)
}
