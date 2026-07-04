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
    /// Row briefly tinted after a "similar transaction" jump, so the eye
    /// lands on the right line once the scroll settles. Cleared ~1.5s later.
    @State private var highlightedID: PersistentIdentifier?

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

    /// Jump from a "similar transaction" line in an expanded card to the
    /// original row: make sure it's visible (active filters or a search
    /// could exclude it), then scroll to it, expand it, and flash a
    /// highlight so the landing spot is unmissable.
    private func jump(to target: Transaction, proxy: ScrollViewProxy) {
        let id = target.persistentModelID
        if !filtered.contains(where: { $0.persistentModelID == id }) {
            clearFilters()
            search = ""
        }
        // Defer one runloop tick so the List has re-rendered with the
        // target row before we scroll — matters when filters were just
        // cleared and the row didn't exist a moment ago.
        DispatchQueue.main.async {
            if reduceMotion {
                expandedID = id
                proxy.scrollTo(id, anchor: .center)
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    expandedID = id
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            highlightedID = id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                withAnimation(.easeOut(duration: 0.4)) {
                    // Guarded so a second jump fired in the meantime keeps
                    // its own highlight.
                    if highlightedID == id { highlightedID = nil }
                }
            }
        }
    }

    /// Surface colour normally; a soft accent wash while this row is the
    /// landing spot of a similar-transaction jump.
    private func rowBackground(_ tx: Transaction) -> Color {
        highlightedID == tx.persistentModelID
            ? Theme.Colors.accent.opacity(0.12)
            : Theme.Colors.surface
    }

    private var list: some View {
        // The reader exists solely for the similar-transaction jumps —
        // `jump(to:proxy:)` scrolls the List to the tapped row.
        ScrollViewReader { proxy in
            listContent(proxy: proxy)
        }
    }

    private func listContent(proxy: ScrollViewProxy) -> some View {
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
                                ExpandedTransactionCard(
                                    transaction: tx,
                                    allTransactions: transactions,
                                    onSelectSimilar: { similar in
                                        jump(to: similar, proxy: proxy)
                                    }
                                )
                                    .transition(reduceMotion
                                        ? .opacity
                                        : .opacity.combined(with: .move(edge: .top)))
                            }
                        }
                            // Anchor for `proxy.scrollTo` in similar-transaction jumps.
                            .id(tx.persistentModelID)
                            .listRowBackground(rowBackground(tx))
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
    /// the shared `Decimal.formattedSignedCurrency`).
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
    /// Called when the user taps a row in the "תנועות דומות" block, with
    /// the tapped transaction. The list answers by scrolling to and
    /// expanding that original row. Nil renders the block as plain text.
    var onSelectSimilar: ((Transaction) -> Void)? = nil

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
                .font(Theme.Typography.bodySmall)
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
                    similarRow(tx)
                }
            }
        }
    }

    /// One similar-transaction line. When the card has an `onSelectSimilar`
    /// handler the line is a button that jumps the list to the original row;
    /// otherwise it renders as a plain (non-interactive) mini row.
    @ViewBuilder
    private func similarRow(_ tx: Transaction) -> some View {
        if let onSelectSimilar {
            Button {
                onSelectSimilar(tx)
            } label: {
                SimilarTransactionRow(transaction: tx, isLink: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("מעבר לתנועה המקורית ברשימה"))
        } else {
            SimilarTransactionRow(transaction: tx, isLink: false)
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
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 18)
            Text(text)
                .font(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Similar transaction mini row

/// A compact echo of `TransactionRow` for the "תנועות דומות" block: the same
/// category badge, title, and kind-coloured signed amount, scaled down and
/// sitting on its own surface tile so it reads as an embedded list row inside
/// the expanded card. The date takes the subtitle slot (the list gets its
/// dates from the day headers; here each row needs its own).
private struct SimilarTransactionRow: View {
    let transaction: Transaction
    /// Whether the row is a tap-to-jump link — adds the forward chevron.
    let isLink: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            badge

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(transaction.date.formatted(
                    .dateTime.locale(Locale(identifier: "he_IL")).day().month(.wide).year()
                ))
                    .font(Theme.Typography.captionSmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text(formattedAmount)
                .font(Theme.Typography.caption)
                .bold()
                .foregroundStyle(amountColor)
                .monospacedDigit()
                .lineLimit(1)

            if isLink {
                // `chevron.forward` auto-mirrors, so it points toward the
                // "go there" direction under the app's RTL layout.
                Image(systemName: "chevron.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        // Surface tile on the card's grey backdrop — the same figure/ground
        // relationship as a list row on the screen background.
        .background(
            Theme.Colors.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
        )
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    // Badge, title, and amount below intentionally mirror `TransactionRow`'s
    // rules (smaller sizes) so the mini row is recognisably "the same row".

    private var badge: some View {
        ZStack {
            Circle()
                .fill(badgeBackground)
                .frame(width: 26, height: 26)
            Image(systemName: badgeSymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(badgeForeground)
        }
    }

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

    /// Same bidi-isolate treatment as the list row, so the sign stays on the
    /// visual left of the number inside the RTL layout.
    private var formattedAmount: String {
        let base = transaction.amount.formatted(.currency(code: transaction.currencyCode))
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
                        // Two native date fields — each taps open Apple's
                        // graphical calendar. Both are capped at today (a
                        // ledger only holds past dates), and "to" can't precede
                        // "from"; `currentInterval` still normalises whole days
                        // and absorbs any flipped pair defensively.
                        DatePicker(
                            "מתאריך",
                            selection: $customRangeStart,
                            in: ...Date.now,
                            displayedComponents: .date
                        )
                        .environment(\.locale, Locale(identifier: "he_IL"))

                        DatePicker(
                            "עד תאריך",
                            selection: $customRangeEnd,
                            in: customRangeStart...Date.now,
                            displayedComponents: .date
                        )
                        .environment(\.locale, Locale(identifier: "he_IL"))
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
            Transaction.self, TransactionAttachment.self, BudgetItem.self, Goal.self, FXRateSnapshot.self
        ],
        inMemory: true
    )
}
