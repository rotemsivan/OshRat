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
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Category.name) private var categories: [Category]

    @State private var search: String = ""
    @State private var typeFilter: TypeFilter = .all
    @State private var selectedCategoryID: PersistentIdentifier?
    @State private var rangeFilter: DateRangeFilter = .all
    @State private var customRangeStart: Date = .now.addingTimeInterval(-30 * 86400)
    @State private var customRangeEnd: Date = .now
    @State private var isShowingFilters: Bool = false

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
                    }
                } header: {
                    Text(dayHeader(group.day))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
    }

    // MARK: - Filtering

    private var filtered: [Transaction] {
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return transactions.filter { tx in
            // Type
            if let target = typeFilter.transactionKind, tx.kind != target { return false }
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
                if let balanceText = formattedBalanceAfter {
                    // Running balance the user saw at the time of entry.
                    // Greyed out so it reads as metadata, not the row's
                    // primary value.
                    Text(balanceText)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var categoryBadge: some View {
        ZStack {
            Circle()
                .fill(badgeBackground)
                .frame(width: 32, height: 32)
            Image(systemName: transaction.category?.symbolName ?? "circle.dashed")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(badgeForeground)
        }
    }

    private var badgeBackground: Color {
        switch transaction.kind {
        case .income:  return Theme.Colors.income.opacity(0.18)
        case .expense: return Theme.Colors.expense.opacity(0.18)
        }
    }

    private var badgeForeground: Color {
        switch transaction.kind {
        case .income:  return Theme.Colors.income
        case .expense: return Theme.Colors.expense
        }
    }

    private var displayTitle: String {
        let trimmed = transaction.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return transaction.category?.name ?? "ללא שם"
    }

    private var subtitle: String {
        var parts: [String] = []
        if let category = transaction.category { parts.append(category.name) }
        if let account = transaction.account { parts.append(account.name) }
        return parts.joined(separator: " • ")
    }

    /// "יתרה: X.XX ACC" line under the amount. Returns nil for older
    /// transactions written before `balanceAfter` existed (or rows
    /// whose account link was nullified, which leaves us without an
    /// accurate currency to format in).
    private var formattedBalanceAfter: String? {
        guard let balance = transaction.balanceAfter,
              let accountCurrency = transaction.account?.currencyCode
        else { return nil }
        return "יתרה: \(balance.formatted(.currency(code: accountCurrency)))"
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
        let sign = transaction.kind == .income ? "+" : "-"
        return "\u{2066}\(sign)\(base)\u{2069}"
    }

    private var amountColor: Color {
        switch transaction.kind {
        case .income:  return Theme.Colors.income
        case .expense: return Theme.Colors.expense
        }
    }
}

// MARK: - Filter enums

/// Three-way type filter. `.all` is the noop case that lets the main
/// filter pipeline skip the predicate entirely.
enum TypeFilter: String, CaseIterable, Identifiable {
    case all
    case income
    case expense

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .all:     return "הכל"
        case .income:  return "הכנסה"
        case .expense: return "הוצאה"
        }
    }

    /// Bridges to the persistence-level enum. Nil for `.all` — that's
    /// the signal to skip filtering by kind.
    var transactionKind: TransactionKind? {
        switch self {
        case .all:     return nil
        case .income:  return .income
        case .expense: return .expense
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
