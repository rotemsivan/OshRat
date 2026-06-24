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
    /// The expand/collapse animation and the row chevron's spin are dropped
    /// when the user has Reduce Motion on.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Live rows only — soft-deleted transactions live in "Recently
    // Deleted" (see `TrashService`) until restored or purged.
    @Query(filter: #Predicate<Transaction> { $0.deletedAt == nil }, sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]
    /// Soft-deleted transactions, surfaced as a count so the toolbar can
    /// offer a "Recently Deleted" entry only when there's something to recover.
    @Query(filter: #Predicate<Transaction> { $0.deletedAt != nil })
    private var deletedTransactions: [Transaction]
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
    /// The row currently expanded into its insights/attachments card, or
    /// `nil` when every row is collapsed. At most one is open at a time, so
    /// a single optional id (rather than a set) is the right model.
    @State private var expandedID: PersistentIdentifier?
    /// Drives the "Recently Deleted" sheet, opened from the toolbar when
    /// there are soft-deleted transactions to recover.
    @State private var isShowingRecentlyDeleted: Bool = false

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
            // Only shown when there's something to recover, so the toolbar
            // stays quiet in the common case. Opens the shared "Recently
            // Deleted" screen (accounts + transactions).
            if !deletedTransactions.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingRecentlyDeleted = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .accessibilityLabel(Text("נמחקו לאחרונה"))
                }
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
        .sheet(isPresented: $isShowingRecentlyDeleted) {
            RecentlyDeletedView()
        }
    }

    // MARK: - Delete

    /// Soft-delete the transaction: reverse its effect on the account
    /// balance (transfer-aware — both sides, or the single income/expense
    /// effect) and hide the row, keeping it recoverable from "Recently
    /// Deleted". `withAnimation` wraps the SwiftData mutation so the
    /// `@Query` refire collapses the row out instead of a hard cut.
    /// Older rows' `balanceAfter` snapshots are deliberately left as-is —
    /// the app treats them as point-in-time and tolerates that drift.
    private func deleteTransaction(_ tx: Transaction) {
        withAnimation {
            TrashService.softDelete(tx, fx: fxSnapshots.first)
            try? modelContext.save()
        }
    }

    // MARK: - Expansion

    /// Whether a row offers the inline insights card. Manual balance-edit
    /// markers are bookkeeping rows, not real income/expense — they carry no
    /// recurrence, amount-vs-average, or attachments worth surfacing, so they
    /// stay collapsed and don't react to a tap.
    private func isExpandable(_ tx: Transaction) -> Bool {
        !tx.isManualBalanceEdit
    }

    /// Toggle the tapped row's inline insights card open/closed. Opening a
    /// new row collapses the previous one (single optional id). The spring is
    /// dropped under Reduce Motion so the height change is an instant cut.
    private func toggleExpand(_ tx: Transaction) {
        guard isExpandable(tx) else { return }
        let id = tx.persistentModelID
        let next: PersistentIdentifier? = (expandedID == id) ? nil : id
        if reduceMotion {
            expandedID = next
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                expandedID = next
            }
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
        .padding(.vertical, Theme.Spacing.md)
    }

    /// A one-tap "clear filters" chip, shown only while type / category /
    /// date filters are active (search has its own clear button). Lets the
    /// user drop back to the full list without reopening the filter sheet.
    /// Lives as the first row of the list (above the day headers).
    private var filterChip: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { clearFilters() }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "xmark.circle.fill")
                Text("איפוס פילטרים")
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.sm)
            .background(Theme.Colors.accent.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("איפוס כל הפילטרים"))
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
            // Quick "clear filters" chip, pinned above the day headers. It's
            // its own headerless section so a tight per-section spacing
            // override sits it close to the first day header — without
            // touching the List's default day-to-day section spacing.
            if hasActiveFilters {
                Section {
                    HStack {
                        filterChip
                        //Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.Colors.surface)
                }
                .listSectionSpacing(Theme.Spacing.xs)
            }

            ForEach(groupedByDay, id: \.day) { group in
                Section {
                    ForEach(group.items) { tx in
                        VStack(spacing: 0) {
                            TransactionRow(
                                transaction: tx,
                                isExpanded: isExpandable(tx) && expandedID == tx.persistentModelID,
                                showsDisclosure: isExpandable(tx)
                            )
                                // Make the whole row a tap target that toggles
                                // its inline insights card. The swipe actions
                                // below still work — a horizontal swipe and a
                                // tap don't compete. Manual balance-edit rows
                                // aren't expandable, so `toggleExpand` ignores
                                // their taps.
                                .contentShape(.rect)
                                .onTapGesture { toggleExpand(tx) }

                            if isExpandable(tx), expandedID == tx.persistentModelID {
                                ExpandedTransactionCard(transaction: tx, allTransactions: transactions)
                                    .transition(reduceMotion
                                        ? .opacity
                                        : .opacity.combined(with: .move(edge: .top)))
                            }
                        }
                            .listRowBackground(Theme.Colors.surface)
                            // Full-bleed surface row (zero horizontal inset)
                            // so the swipe actions reveal the white row
                            // itself rather than the gray gutter an inset
                            // group leaves around it — matching the look of
                            // the dashboard's accounts card. The row content
                            // carries its own horizontal padding instead.
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                // Order matters: SwiftUI lays the first
                                // item closest to the swipe edge, so Delete
                                // first puts it at the trailing edge — the
                                // destructive slot users expect, and the one
                                // a full swipe triggers. Unified with the
                                // accounts and budget lists.
                                //
                                // Icon-only (`Image`, not `Label`) for a
                                // compact look that doesn't depend on row
                                // height; `accessibilityLabel` keeps the
                                // spoken name for VoiceOver.
                                Button(role: .destructive) {
                                    deleteTransaction(tx)
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
        // A small top inset above the chip. Day-to-day section spacing stays
        // at the List default — only the chip section overrides its own
        // spacing (above) to sit tight against the first day header.
        .contentMargins(.top, 10, for: .scrollContent)
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
            // Cover *whole* days: the range calendar stores each endpoint at
            // start-of-day, so without this a transaction logged later on the
            // end day (any time after midnight) would fall outside the range.
            // Normalise to [start of the first day, start of the day after the
            // last] and let `min`/`max` absorb a flipped start/end.
            let calendar = Calendar.current
            let lo = calendar.startOfDay(for: min(customRangeStart, customRangeEnd))
            let hiDay = calendar.startOfDay(for: max(customRangeStart, customRangeEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: hiDay) ?? hiDay
            return DateInterval(start: lo, end: end)
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
    /// Whether this row's inline insights card is open — drives the
    /// disclosure chevron's direction.
    var isExpanded: Bool = false
    /// Whether this row can expand into an insights card. Manual
    /// balance-edit rows can't, so they hide the chevron and drop the
    /// tap-to-expand affordance from VoiceOver.
    var showsDisclosure: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            categoryBadge

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(displayTitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    // A small paperclip flags rows that carry a receipt /
                    // invoice, so the user can spot them without expanding.
                    if transaction.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
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

            // Disclosure chevron — points down when collapsed, flips up when
            // the insights card is open. Hidden from VoiceOver since the whole
            // row already exposes a button trait + hint. Its width is *always*
            // reserved (a fixed frame + opacity, rather than removing the view)
            // so the amount column lines up across every row — otherwise a
            // non-expandable row like a manual balance edit, which has no
            // chevron, would let its amount slide left out of alignment.
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .frame(width: 12)
                .opacity(showsDisclosure ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
                .accessibilityHidden(true)
        }
        // Rows are full-bleed in the list (zero row insets) so the swipe
        // actions sit on the white surface; the content supplies its own
        // padding to match the screen's horizontal rhythm.
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        // One combined VoiceOver element — title, amount, balances. Expandable
        // rows also carry a button trait + hint so the affordance is
        // discoverable; manual-edit rows have nothing to expand, so they stay
        // a plain, hint-free element.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(showsDisclosure ? .isButton : [])
        .accessibilityHint(disclosureHint)
    }

    /// VoiceOver hint for the row. Only expandable rows advertise the
    /// tap-to-expand behaviour; manual-edit rows stay silent.
    private var disclosureHint: Text {
        guard showsDisclosure else { return Text(verbatim: "") }
        return Text(isExpanded ? "הקש לסגירת התובנות" : "הקש להצגת תובנות וקבצים")
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

// MARK: - Expanded insights card

/// The card revealed under a row when it's tapped open. Surfaces the
/// previously-hidden note, a few computed insights (how often this recurs,
/// how the amount compares, when it was last seen, a timing pattern), any
/// attached files, and a short list of similar past transactions.
///
/// All the number-crunching lives in the pure `TransactionInsights` value
/// type; this view only formats those facts into Hebrew. Insights are
/// computed lazily here — only the single open row builds them, and the
/// ledger is tiny by design (same rationale as the list's client-side
/// filtering), so there's no need to cache.
private struct ExpandedTransactionCard: View {
    let transaction: Transaction
    let allTransactions: [Transaction]

    /// Relative-time formatter pinned to Hebrew, e.g. "לפני 8 ימים".
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        let insights = TransactionInsights.make(for: transaction, in: allTransactions)

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if !trimmedNote.isEmpty { noteBlock }
            if insights.hasMeaningfulInsights { insightsBlock(insights) }
            if !transaction.attachments.isEmpty { attachmentsBlock }
            if !insights.similar.isEmpty { similarBlock(insights.similar) }
            if isEmpty(insights) { emptyHint }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(
            Theme.Colors.background,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: Blocks

    private var noteBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            blockLabel("פירוט")
            Text(trimmedNote)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func insightsBlock(_ insights: TransactionInsights) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            blockLabel("תובנות")
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if let line = occurrenceLine(insights) {
                    InsightLine(symbol: "number.square", text: line)
                }
                if let cadence = insights.cadence {
                    InsightLine(symbol: "repeat", text: cadenceText(cadence))
                }
                if let line = amountComparisonLine(insights) {
                    InsightLine(symbol: "chart.bar", text: line)
                }
                if let last = insights.lastOccurrence {
                    InsightLine(
                        symbol: "clock.arrow.circlepath",
                        text: "נראתה לאחרונה \(Self.relativeFormatter.localizedString(for: last, relativeTo: .now))"
                    )
                }
                if let pattern = insights.dayPattern {
                    InsightLine(symbol: "calendar", text: dayPatternText(pattern))
                }
            }
        }
    }

    private var attachmentsBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            blockLabel("קבצים מצורפים")
            // Sorted oldest-first for a stable order matching the editor.
            AttachmentStrip(attachments: transaction.attachments.sorted { $0.createdAt < $1.createdAt })
        }
    }

    private func similarBlock(_ similar: [Transaction]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            blockLabel("תנועות דומות")
            VStack(spacing: Theme.Spacing.xs) {
                ForEach(similar) { tx in
                    HStack {
                        Text(tx.date.formatted(.dateTime.locale(Locale(identifier: "he_IL")).day().month(.abbreviated)))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer(minLength: Theme.Spacing.sm)
                        Text("\u{2066}\(tx.amount.formatted(.currency(code: tx.currencyCode)))\u{2069}")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var emptyHint: some View {
        Text("אין עדיין תובנות לתנועה הזו — היא תופיע כאן כשיהיו לה תנועות דומות.")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Helpers

    private var trimmedNote: String {
        transaction.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when there's genuinely nothing to show — keeps the expanded area
    /// from rendering as an empty box.
    private func isEmpty(_ insights: TransactionInsights) -> Bool {
        trimmedNote.isEmpty
            && !insights.hasMeaningfulInsights
            && transaction.attachments.isEmpty
            && insights.similar.isEmpty
    }

    private func blockLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func occurrenceLine(_ insights: TransactionInsights) -> String? {
        guard insights.occurrenceCount > 1 else { return nil }
        return "נרשמה \(timesText(insights.occurrenceCount))"
    }

    /// Hebrew count phrasing: 2 → "פעמיים", otherwise "N פעמים".
    private func timesText(_ count: Int) -> String {
        count == 2 ? "פעמיים" : "\(count) פעמים"
    }

    private func cadenceText(_ cadence: Cadence) -> String {
        switch cadence {
        case .weekly:    return "חוזרת בערך כל שבוע"
        case .biweekly:  return "חוזרת בערך כל שבועיים"
        case .monthly:   return "חוזרת בערך כל חודש"
        case .quarterly: return "חוזרת בערך כל שלושה חודשים"
        case .yearly:    return "חוזרת בערך פעם בשנה"
        case .irregular(let days): return "חוזרת בערך כל \(days) ימים"
        }
    }

    /// "X% more/less than usual" with the typical amount, or "typical" when
    /// it's within ~5% of the average. `nil` when there's no baseline.
    private func amountComparisonLine(_ insights: TransactionInsights) -> String? {
        guard let delta = insights.amountDeltaFraction else { return nil }
        let percent = Int((abs(delta) * 100).rounded())
        guard let average = insights.averageAmount else { return nil }
        let averageText = average.formatted(.currency(code: transaction.currencyCode))
        if percent < 5 {
            return "סכום אופייני (הממוצע: \(averageText))"
        }
        let direction = delta > 0 ? "יותר" : "פחות"
        return "\u{2066}\(percent)%\u{2069} \(direction) מהרגיל (הממוצע: \(averageText))"
    }

    private func dayPatternText(_ pattern: DayPattern) -> String {
        switch pattern {
        case .weekend:      return "בדרך כלל בסופי שבוע"
        case .startOfMonth: return "בדרך כלל בתחילת החודש"
        case .midMonth:     return "בדרך כלל באמצע החודש"
        case .endOfMonth:   return "בדרך כלל בסוף החודש"
        }
    }
}

/// One labelled insight: an accent glyph on the leading side, the Hebrew
/// fact beside it.
private struct InsightLine: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 18)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
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
                    // Drop the grouped "card" backing so the segmented control
                    // sits directly on the form background — the filled frame
                    // around it read as visual clutter.
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: 0, bottom: Theme.Spacing.xs, trailing: 0))
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
                        // One calendar: tap a start day, then an end day, and
                        // the span in between is marked. Both dates are written
                        // straight back to the filter bindings.
                        DateRangeCalendar(start: $customRangeStart, end: $customRangeEnd)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(
                                top: Theme.Spacing.sm,
                                leading: Theme.Spacing.sm,
                                bottom: Theme.Spacing.sm,
                                trailing: Theme.Spacing.sm
                            ))
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

// MARK: - Date range calendar

/// A month calendar that picks a contiguous date range for the custom
/// filter. The first tap sets the start (collapsing the range to that one
/// day); the next tap on the same-or-later day sets the end, marking every
/// day in between; a further tap starts a fresh range. Both endpoints are
/// written straight back to the `start` / `end` bindings.
///
/// Mirrors the month-grid mechanics of `BudgetCalendarView` (six-week grid,
/// RTL-aware weekday order, month paging) but trades the per-day budget dots
/// for range highlighting.
private struct DateRangeCalendar: View {
    @Binding var start: Date
    @Binding var end: Date

    /// First day of the month on screen.
    @State private var visibleMonth: Date
    /// After a fresh start is set, the next tap completes the range by
    /// setting the end. Reset to `false` once a range is complete, so the
    /// following tap begins a new selection.
    @State private var selectingEnd: Bool = false
    /// When true the day grid is swapped for month + year wheels, so the
    /// user can jump straight to any month instead of paging one at a time.
    @State private var isPickingMonth: Bool = false
    /// Lets the horizontal swipe map to previous / next month the right way
    /// round under RTL.
    @Environment(\.layoutDirection) private var layoutDirection

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "he_IL")
        return calendar
    }()

    init(start: Binding<Date>, end: Binding<Date>) {
        _start = start
        _end = end
        _visibleMonth = State(initialValue: Self.startOfMonth(for: start.wrappedValue))
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            header
            if isPickingMonth {
                MonthYearPicker(month: $visibleMonth)
            } else {
                weekdayHeader
                LazyVGrid(columns: Self.columns, spacing: Theme.Spacing.xs) {
                    ForEach(gridDays, id: \.self) { day in
                        dayCell(day)
                            .contentShape(.rect)
                            .onTapGesture { tap(day) }
                    }
                }
                // Swipe the grid left / right to page months (RTL-aware), so
                // navigation isn't only the chevrons.
                .contentShape(.rect)
                .gesture(monthSwipe)
            }
            summary
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            navButton(systemName: "chevron.backward", label: "החודש הקודם") { shiftMonth(by: -1) }
                .opacity(isPickingMonth ? 0 : 1)
                .disabled(isPickingMonth)
            Spacer()
            // Tap the label to reveal the month / year wheels and jump anywhere.
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isPickingMonth.toggle() }
            } label: {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(monthYearLabel)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .rotationEffect(.degrees(isPickingMonth ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("בחירת חודש ושנה"))
            Spacer()
            navButton(systemName: "chevron.forward", label: "החודש הבא") { shiftMonth(by: 1) }
                .opacity(isPickingMonth ? 0 : 1)
                .disabled(isPickingMonth)
        }
    }

    private func navButton(
        systemName: String,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.accent)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var weekdayHeader: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(orderedWeekdays.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Day cell

    private func dayCell(_ day: Date) -> some View {
        let d = calendar.startOfDay(for: day)
        let inMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
        let lo = calendar.startOfDay(for: min(start, end))
        let hi = calendar.startOfDay(for: max(start, end))
        let inSpan = d >= lo && d <= hi
        let isEndpoint = d == lo || d == hi
        // The band reaches a cell's leading edge whenever the range continues
        // to earlier days, and the trailing edge whenever it continues to
        // later days. Because `LazyVGrid` fills leading→trailing (and mirrors
        // under RTL), "earlier" is always the leading side — so this is
        // direction-agnostic. The two half-fills, with zero column spacing,
        // join into one continuous band; at a week's edge a row simply runs to
        // its own edge, which reads as the band wrapping to the next line.
        let fillLeading = inSpan && d > lo
        let fillTrailing = inSpan && d < hi

        // Full-width ZStack (not a `.background` on the 32-pt number) so the
        // band's two half-rectangles span the whole cell and meet the
        // neighbours' — that's what makes the highlight read as one band.
        return ZStack {
            if inSpan {
                HStack(spacing: 0) {
                    Rectangle().fill(fillLeading ? bandColor : Color.clear)
                    Rectangle().fill(fillTrailing ? bandColor : Color.clear)
                }
                .frame(height: 32)
            }
            if isEndpoint {
                Circle().fill(Theme.Colors.accent).frame(width: 32, height: 32)
            }
            Text(dayNumber(day))
                .font(Theme.Typography.body)
                .monospacedDigit()
                .foregroundStyle(numberColor(isEndpoint: isEndpoint, inSpan: inSpan))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .padding(.vertical, 2)
        .opacity(inMonth ? 1 : 0.3)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isEndpoint ? .isSelected : [])
        .accessibilityLabel(Text(accessibilityLabel(day)))
    }

    /// Faint accent wash for the range band — light enough that the day
    /// numbers stay readable on top.
    private var bandColor: Color { Theme.Colors.accent.opacity(0.18) }

    private func numberColor(isEndpoint: Bool, inSpan: Bool) -> Color {
        // Endpoints sit on a solid accent disc (white reads best); in-between
        // days keep the normal label colour for contrast on the faint band.
        isEndpoint ? .white : Theme.Colors.textPrimary
    }

    // MARK: Summary

    private var summary: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "calendar")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(summaryText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
        }
    }

    private var summaryText: String {
        let currentYear = calendar.component(.year, from: .now)
        if selectingEnd {
            // Show the start's year if it isn't the current one, so a date
            // being carried into the hint never reads ambiguously.
            let needsYear = calendar.component(.year, from: start) != currentYear
            return "מ-\(shortDate(start, includeYear: needsYear)) · בחרו תאריך סיום"
        }
        let lo = min(start, end)
        let hi = max(start, end)
        // Surface the year when the two endpoints span different years (so a
        // cross-year range is unambiguous) or when the range sits outside the
        // current year entirely.
        let needsYear = calendar.component(.year, from: lo) != calendar.component(.year, from: hi)
            || calendar.component(.year, from: lo) != currentYear
        if calendar.isDate(lo, inSameDayAs: hi) {
            return shortDate(lo, includeYear: needsYear)
        }
        return "\(shortDate(lo, includeYear: needsYear)) – \(shortDate(hi, includeYear: needsYear))"
    }

    // MARK: Interaction

    private func tap(_ day: Date) {
        let d = calendar.startOfDay(for: day)
        // Tapping a spill-over day flips to its month, so a range can be
        // dragged across the month boundary.
        if !calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = Self.startOfMonth(for: day, calendar: calendar)
        }
        if selectingEnd && d >= calendar.startOfDay(for: start) {
            end = d
            selectingEnd = false
        } else {
            start = d
            end = d
            selectingEnd = true
        }
    }

    private func shiftMonth(by delta: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        visibleMonth = Self.startOfMonth(for: shifted, calendar: calendar)
    }

    /// A mostly-horizontal swipe pages the month. Under RTL a rightward drag
    /// goes forward (later) — the mirror of the LTR convention — so it lines
    /// up with the visual direction of the next-month chevron.
    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) else { return }
                let forward = layoutDirection == .rightToLeft ? (dx > 0) : (dx < 0)
                shiftMonth(by: forward ? 1 : -1)
            }
    }

    // MARK: Derived data

    /// Six weeks of days from the first day of the grid's first week, so the
    /// grid height stays constant from month to month.
    private var gridDays: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else { return [] }
        var days: [Date] = []
        var cursor = firstWeek.start
        for _ in 0..<42 {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// Weekday header symbols in display order (honours `firstWeekday`).
    private var orderedWeekdays: [String] {
        let symbols = calendar.veryShortWeekdaySymbols   // index 0 == Sunday
        let offset = calendar.firstWeekday - 1
        return (0..<7).map { symbols[($0 + offset) % 7] }
    }

    private func dayNumber(_ day: Date) -> String {
        day.formatted(.dateTime.locale(Locale(identifier: "he_IL")).day())
    }

    private func shortDate(_ day: Date, includeYear: Bool) -> String {
        let he = Locale(identifier: "he_IL")
        return includeYear
            ? day.formatted(.dateTime.locale(he).day().month(.abbreviated).year())
            : day.formatted(.dateTime.locale(he).day().month(.abbreviated))
    }

    private var monthYearLabel: String {
        visibleMonth.formatted(.dateTime.locale(Locale(identifier: "he_IL")).month(.wide).year())
    }

    private func accessibilityLabel(_ day: Date) -> String {
        day.formatted(.dateTime.locale(Locale(identifier: "he_IL")).weekday(.wide).day().month(.wide))
    }

    // Zero column spacing so adjacent range-band fills meet with no gap; the
    // 32-pt day discs are inset within each (wider) cell, so cells still read
    // as distinct.
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private static func startOfMonth(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}

#Preview {
    NavigationStack {
        TransactionsListView()
    }
    .modelContainer(
        for: [
            UserProfile.self, Account.self, Holding.self, Category.self,
            Transaction.self, TransactionAttachment.self, BudgetItem.self, Goal.self, FXRateSnapshot.self
        ],
        inMemory: true
    )
}
