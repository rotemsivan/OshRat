import SwiftUI
import SwiftData

/// Full log of every transaction the user has entered, grouped by day
/// (newest first) and filterable along four axes:
///
///   * **Free-text** — searches title, note, and category name.
///   * **Type** — all / הכנסה / הוצאה.
///   * **Category** — any of the seeded or user-added categories.
///   * **Date range** — last 7d / 30d / 90d / all-time, plus a custom
///     range picker when the user wants something specific.
///
/// All filtering happens client-side over the `@Query` result. The
/// dataset is tiny by design (this is a hand-entered ledger, not a bank
/// feed) so re-filtering on every keystroke is fine.
struct TransactionsListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Category.name) private var categories: [Category]
    /// Newest snapshot first — `fxSnapshots.first` is the freshest cached
    /// rate set, used to reverse a deleted transaction's balance effect
    /// when its currency differs from its account's.
    @Query(sort: \FXRateSnapshot.fetchedAt, order: .reverse) private var fxSnapshots: [FXRateSnapshot]

    @State private var search: String = ""
    @State private var typeFilter: TypeFilter = .all
    @State private var selectedCategoryID: PersistentIdentifier?
    @State private var rangeFilter: DateRangeFilter = .all
    @State private var customRangeStart: Date = .now.addingTimeInterval(-30 * 86400)
    @State private var customRangeEnd: Date = .now
    @State private var isShowingFilters: Bool = false

    /// The transaction whose editor sheet is open, or `nil`. Reuses the
    /// "new transaction" sheet in edit mode.
    @State private var editingTransaction: Transaction?
    /// Set when the user taps "מחיקה" on a swipe action. Drives the
    /// confirmation alert; never persists between renders, so `@State`
    /// (not `@Binding`) is the right ownership — same pattern as the
    /// accounts card on the dashboard.
    @State private var transactionPendingDelete: Transaction?

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                searchBar
                content
            }
        }
        .navigationTitle(Text("תנועות"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingFilters = true
                } label: {
                    Image(systemName: hasActiveFilters
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(Theme.Colors.accent)
                }
                .accessibilityLabel(Text("פילטרים"))
            }
        }
        .sheet(isPresented: $isShowingFilters) {
            FiltersSheet(
                typeFilter: $typeFilter,
                selectedCategoryID: $selectedCategoryID,
                rangeFilter: $rangeFilter,
                customRangeStart: $customRangeStart,
                customRangeEnd: $customRangeEnd,
                categories: categories
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingTransaction) { tx in
            // Same sheet as "new transaction", opened in edit mode. It
            // owns the SwiftData update (and the balance adjustment) so
            // the list just hands it the row.
            NewTransactionSheet(transaction: tx)
        }
        .alert(
            Text("מחיקת תנועה"),
            isPresented: deleteAlertBinding,
            presenting: transactionPendingDelete
        ) { tx in
            Button("מחיקה", role: .destructive) {
                deleteTransaction(tx)
            }
            Button("ביטול", role: .cancel) {}
        } message: { _ in
            Text("אתה בטוח שברצונך למחוק את התנועה? יתרת החשבון תעודכן בהתאם.")
        }
    }

    // MARK: - Delete

    /// `.alert(presenting:)` wants a `Binding<Bool>` for `isPresented`;
    /// bridge it through the optional pending transaction so dismissing
    /// clears the pending row in one place. Mirrors `AssetsSummaryCard`.
    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { transactionPendingDelete != nil },
            set: { if !$0 { transactionPendingDelete = nil } }
        )
    }

    /// Reverse the transaction's effect on its account balance, then
    /// delete it. `withAnimation` wraps the SwiftData mutation so the
    /// `@Query` refire collapses the row out instead of a hard cut.
    /// Older rows' `balanceAfter` snapshots are deliberately left as-is —
    /// the app treats them as point-in-time and tolerates that drift.
    private func deleteTransaction(_ tx: Transaction) {
        withAnimation {
            // Transfer-aware: unwinds *both* sides of a transfer, or the
            // single account effect of an income/expense row.
            tx.reverseEffect(using: fxSnapshots.first)
            modelContext.delete(tx)
            try? modelContext.save()
        }
    }

    // MARK: - Body

    /// Always-visible search row pinned above the day-grouped list.
    /// Replaces the previous `.searchable` toolbar entry — that one
    /// collapses under the nav title until the user pulls down, which
    /// hid the affordance on long lists.
    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(Theme.Colors.textSecondary)
            HebrewTextField("חיפוש בתנועות", text: $search)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("ניקוי חיפוש"))
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(height: 32)
        .background(Theme.Colors.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Theme.Colors.separator, lineWidth: 1)
        )
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xs)
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(transactions.isEmpty ? "עדיין לא נרשמו תנועות." : "אין תנועות שתואמות לפילטרים.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            if hasActiveFilters && !transactions.isEmpty {
                Button("איפוס פילטרים") {
                    clearFilters()
                }
                .buttonStyle(.bordered)
                .tint(Theme.Colors.accent)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(groupedByDay, id: \.day) { group in
                Section {
                    ForEach(group.items) { tx in
                        TransactionRow(transaction: tx)
                            .listRowBackground(Theme.Colors.surface)
                            // Full-bleed surface row (zero horizontal inset)
                            // so the swipe actions reveal the white row
                            // itself rather than the gray gutter an inset
                            // group leaves around it — matching the look of
                            // the dashboard's accounts card. The row content
                            // carries its own horizontal padding instead.
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // Order matters: SwiftUI lays the first
                                // item closest to the swipe edge, so Delete
                                // first puts it at the trailing edge — the
                                // destructive slot users expect. Mirrors the
                                // accounts card on the dashboard.
                                //
                                // Icon-only (`Image`, not `Label`) for a
                                // compact look that doesn't depend on row
                                // height; `accessibilityLabel` keeps the
                                // spoken name for VoiceOver.
                                Button(role: .destructive) {
                                    transactionPendingDelete = tx
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel(Text("מחיקה"))

                                // Manual balance-edit markers are
                                // bookkeeping rows, not real income/expense,
                                // and may be tied to a non-current account
                                // the editor can't represent — so they're
                                // delete-only (deleting reverses the manual
                                // adjustment). Transfers are delete-only too:
                                // the editor models a single account, not a
                                // two-sided move, so we don't reopen them.
                                if !tx.isManualBalanceEdit && !tx.isTransfer {
                                    Button {
                                        editingTransaction = tx
                                    } label: {
                                        Image(systemName: "pencil")
                                    }
                                    .tint(Theme.Colors.accent)
                                    .accessibilityLabel(Text("עריכה"))
                                }
                            }
                    }
                } header: {
                    Text(dayHeader(group.day))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        // Align the day label with the row content's
                        // horizontal padding now that rows are full-bleed.
                        .padding(.horizontal, Theme.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // White (surface), not the gray screen background: the swipe
        // actions reveal whatever sits *behind* the row, so a surface
        // backdrop puts the buttons on white — matching the dashboard's
        // accounts card, where the list lives on a white card. The row
        // backgrounds are surface too, so the whole list reads as one
        // continuous white sheet with no gray gutter beside the buttons.
        .background(Theme.Colors.surface)
    }

    // MARK: - Filtering

    private var filtered: [Transaction] {
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return transactions.filter { tx in
            // Type (transfer-aware: income/expense exclude transfers, and
            // the transfer filter shows only them).
            if !typeFilter.matches(tx) { return false }
            // Category
            if let id = selectedCategoryID, tx.category?.persistentModelID != id { return false }
            // Date range
            if let interval = currentInterval, !interval.contains(tx.date) { return false }
            // Free-text
            if !trimmedSearch.isEmpty {
                let needle = trimmedSearch.lowercased()
                let haystacks = [
                    tx.title,
                    tx.note,
                    tx.category?.name ?? ""
                ].joined(separator: " ").lowercased()
                if !haystacks.contains(needle) { return false }
            }
            return true
        }
    }

    /// The date interval implied by the current range filter. `.all`
    /// returns nil — meaning "don't filter by date at all", which lets
    /// the main filter pipeline short-circuit cleanly.
    private var currentInterval: DateInterval? {
        let now = Date()
        switch rangeFilter {
        case .all:
            return nil
        case .last7:
            return DateInterval(start: now.addingTimeInterval(-7 * 86400), end: now)
        case .last30:
            return DateInterval(start: now.addingTimeInterval(-30 * 86400), end: now)
        case .last90:
            return DateInterval(start: now.addingTimeInterval(-90 * 86400), end: now)
        case .custom:
            // Guard against the user flipping start past end — clamp to
            // the smaller range so we always return a valid interval.
            let start = min(customRangeStart, customRangeEnd)
            let end   = max(customRangeStart, customRangeEnd)
            return DateInterval(start: start, end: end)
        }
    }

    private var hasActiveFilters: Bool {
        typeFilter != .all
            || selectedCategoryID != nil
            || rangeFilter != .all
    }

    private func clearFilters() {
        typeFilter = .all
        selectedCategoryID = nil
        rangeFilter = .all
    }

    // MARK: - Grouping

    /// Bucket the filtered list into day-keyed groups, newest day first.
    /// Calendar.startOfDay collapses time-of-day so two transactions on
    /// the same calendar day always share a group, regardless of the
    /// minute they were entered.
    private var groupedByDay: [DayGroup] {
        let calendar = Calendar.current
        var buckets: [Date: [Transaction]] = [:]
        for tx in filtered {
            let day = calendar.startOfDay(for: tx.date)
            buckets[day, default: []].append(tx)
        }
        return buckets
            .map { DayGroup(day: $0.key, items: $0.value) }
            .sorted { $0.day > $1.day }
    }
    
    private func dayHeader(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day)     { return "היום" }
        if calendar.isDateInYesterday(day) { return "אתמול" }
        return day.formatted(
            .dateTime
                .locale(Locale(identifier: "he_IL"))
                .day().month(.wide).year()
        )
    }
}

// MARK: - Day group

private struct DayGroup {
    let day: Date
    let items: [Transaction]
}

// MARK: - Row

/// One transaction line. Title (or fallback "(ללא שם)") on top, category
/// + account underneath, amount on the trailing side coloured by kind.
private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            categoryBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedAmount)
                    .font(Theme.Typography.amount)
                    .foregroundStyle(amountColor)
                    .monospacedDigit()
                    .lineLimit(1)
                // Running balance(s) the user saw at the time of entry —
                // one line for an income/expense, both sides for a transfer.
                // Greyed out so they read as metadata, not the row's primary
                // value. `enumerated` keeps the id stable even if two lines
                // ever format identically (duplicate account names).
                ForEach(Array(balanceLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        // Rows are full-bleed in the list (zero row insets) so the swipe
        // actions sit on the white surface; the content supplies its own
        // padding to match the screen's horizontal rhythm.
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var categoryBadge: some View {
        ZStack {
            Circle()
                .fill(badgeBackground)
                .frame(width: 32, height: 32)
            Image(systemName: badgeSymbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(badgeForeground)
        }
    }

    /// Transfers get the two-way arrow (they carry no category); everything
    /// else uses its category glyph, falling back to a dashed circle.
    private var badgeSymbol: String {
        if transaction.isTransfer { return "arrow.left.arrow.right" }
        return transaction.category?.symbolName ?? "circle.dashed"
    }

    private var badgeBackground: Color {
        if transaction.isTransfer { return Theme.Colors.accent.opacity(0.18) }
        switch transaction.kind {
        case .income:  return Theme.Colors.income.opacity(0.18)
        case .expense: return Theme.Colors.expense.opacity(0.18)
        }
    }

    private var badgeForeground: Color {
        if transaction.isTransfer { return Theme.Colors.accent }
        switch transaction.kind {
        case .income:  return Theme.Colors.income
        case .expense: return Theme.Colors.expense
        }
    }

    private var displayTitle: String {
        let trimmed = transaction.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if transaction.isTransfer { return "העברה" }
        return transaction.category?.name ?? "ללא שם"
    }

    private var subtitle: String {
        if transaction.isTransfer {
            // "{source} ← {destination}": both names are Hebrew (RTL), so
            // the neutral arrow resolves between them and visually points
            // from the source (right) to the destination (left) — the same
            // direction as the diagram in the entry sheet.
            let source = transaction.account?.name ?? "—"
            let destination = transaction.destinationAccount?.name ?? "—"
            return "\(source) ← \(destination)"
        }
        var parts: [String] = []
        if let category = transaction.category { parts.append(category.name) }
        if let account = transaction.account { parts.append(account.name) }
        return parts.joined(separator: " • ")
    }

    /// Running-balance line(s) shown under the amount. An income/expense
    /// row shows the single "יתרה: X.XX ACC" the user saw at entry. A
    /// transfer shows *both* sides — the source's balance after the debit
    /// and the destination's after the credit — each tagged with its
    /// account name so the two don't blur into one another (and so they
    /// map back to the "source ← destination" subtitle).
    private var balanceLines: [String] {
        if transaction.isTransfer {
            // Source first (it pairs with the debit shown as the row's main
            // amount), destination below.
            return [
                balanceLine(
                    transaction.balanceAfter,
                    currency: transaction.account?.currencyCode,
                    name: transaction.account?.name
                ),
                balanceLine(
                    transaction.destinationBalanceAfter,
                    currency: transaction.destinationAccount?.currencyCode,
                    name: transaction.destinationAccount?.name
                )
            ].compactMap { $0 }
        }
        return [balanceLine(transaction.balanceAfter, currency: transaction.account?.currencyCode, name: nil)]
            .compactMap { $0 }
    }

    /// Format one balance line, or nil when there's nothing trustworthy to
    /// show — a missing balance (legacy rows from before the snapshot
    /// existed) or a missing currency (a nullified account link leaves no
    /// accurate currency to format in). `name`, when given, prefixes the
    /// line ("עו״ש: …") so a transfer's two balances stay distinguishable;
    /// without it the plain "יתרה: …" label is used.
    private func balanceLine(_ balance: Decimal?, currency: String?, name: String?) -> String? {
        guard let balance, let currency else { return nil }
        let formatted = balance.formatted(.currency(code: currency))
        if let name { return "\(name): \(formatted)" }
        return "יתרה: \(formatted)"
    }

    /// Signed amount — income shows with a leading "+" so the eye can
    /// scan income/expense down a column without re-reading the colour.
    ///
    /// Wrapped in U+2066 LRI … U+2069 PDI so the bidi-neutral "+"/"-"
    /// always lands on the visual left of the number. Without the
    /// isolate, inside the Hebrew RTL view the sign inherits RTL
    /// direction and ends up on the visual right (same bug fixed in
    /// `BudgetSummaryCard.formattedNet` / `MonthlySummaryCard.formattedNet`).
    private var formattedAmount: String {
        let base = transaction.amount.formatted(.currency(code: transaction.currencyCode))
        // A transfer is neither + nor − to net worth — money just moves
        // between the user's own accounts. Show it unsigned (the accent
        // colour and the ⇄ badge already mark it as a transfer) so it
        // doesn't read as income or expense in the column.
        if transaction.isTransfer {
            return "\u{2066}\(base)\u{2069}"
        }
        let sign = transaction.kind == .income ? "+" : "-"
        return "\u{2066}\(sign)\(base)\u{2069}"
    }

    private var amountColor: Color {
        if transaction.isTransfer { return Theme.Colors.accent }
        switch transaction.kind {
        case .income:  return Theme.Colors.income
        case .expense: return Theme.Colors.expense
        }
    }
}

// MARK: - Filter enums

/// Four-way type filter. `.all` is the noop case that matches everything;
/// `.transfer` is its own bucket alongside income and expense.
enum TypeFilter: String, CaseIterable, Identifiable {
    case all
    case income
    case expense
    case transfer

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .all:      return "הכל"
        case .income:   return "הכנסה"
        case .expense:  return "הוצאה"
        case .transfer: return "העברה"
        }
    }

    /// Whether a transaction passes this filter. Transfers are stored with
    /// a placeholder `kind`, so `.income`/`.expense` explicitly exclude
    /// them (otherwise a transfer would leak into the expense list), and
    /// `.transfer` matches only them.
    func matches(_ tx: Transaction) -> Bool {
        switch self {
        case .all:      return true
        case .income:   return !tx.isTransfer && tx.kind == .income
        case .expense:  return !tx.isTransfer && tx.kind == .expense
        case .transfer: return tx.isTransfer
        }
    }
}

/// Coarse "how far back" buckets, plus a custom date-range escape hatch.
/// Snapped windows handle ~90% of "show me recent stuff"; custom covers
/// the "let me see July" case.
enum DateRangeFilter: String, CaseIterable, Identifiable {
    case all
    case last7
    case last30
    case last90
    case custom

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .all:    return "הכל"
        case .last7:  return "7 ימים"
        case .last30: return "30 ימים"
        case .last90: return "90 ימים"
        case .custom: return "טווח מותאם"
        }
    }
}

// MARK: - Filters sheet

/// Modal filter editor — separated from the list itself so the toolbar
/// stays uncluttered and the toolbar icon can act as the "filters open"
/// affordance.
private struct FiltersSheet: View {
    @Binding var typeFilter: TypeFilter
    @Binding var selectedCategoryID: PersistentIdentifier?
    @Binding var rangeFilter: DateRangeFilter
    @Binding var customRangeStart: Date
    @Binding var customRangeEnd: Date

    let categories: [Category]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("סוג", selection: $typeFilter) {
                        ForEach(TypeFilter.allCases) { t in
                            Text(t.hebrewLabel).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("סוג תנועה")
                }

                Section {
                    Picker("קטגוריה", selection: $selectedCategoryID) {
                        Text("הכל").tag(PersistentIdentifier?.none)
                        ForEach(categories.semanticallyUnique) { category in
                            Text(category.name).tag(Optional(category.persistentModelID))
                        }
                    }
                } header: {
                    Text("קטגוריה")
                }

                Section {
                    Picker("טווח", selection: $rangeFilter) {
                        ForEach(DateRangeFilter.allCases) { r in
                            Text(r.hebrewLabel).tag(r)
                        }
                    }

                    if rangeFilter == .custom {
                        DatePicker("מתאריך", selection: $customRangeStart, displayedComponents: .date)
                        DatePicker("עד תאריך", selection: $customRangeEnd, displayedComponents: .date)
                    }
                } header: {
                    Text("טווח תאריכים")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .font(Theme.Typography.body)
            .navigationTitle(Text("פילטרים"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
        }
        .tint(Theme.Colors.accent)
    }
}

#Preview {
    NavigationStack {
        TransactionsListView()
    }
    .modelContainer(
        for: [
            UserProfile.self, Account.self, Holding.self, Category.self,
            Transaction.self, BudgetItem.self, Goal.self, FXRateSnapshot.self
        ],
        inMemory: true
    )
}
