import SwiftUI

/// "My assets" card — the hero of the dashboard.
///
/// Headline is a single big total in the user's preferred currency,
/// combining every account and every holding via the cached FX
/// snapshot. Below it sits a small "מומר משער של DATE" line so the
/// user can see how fresh the FX data is. Per-account rows below that
/// still display in each account's *own* currency — that's where you
/// look when you want a per-account read.
///
/// Tapping an account row opens its `AccountEditorSheet` (unified with
/// the budget and transaction lists). The trailing edge swipes to a
/// trash icon that, after a confirmation alert, soft-deletes the account
/// (the parent hides it via `TrashService` inside a `withAnimation`
/// block so the row collapses smoothly, and it stays recoverable from
/// "Recently Deleted"). The leading edge swipes to the favourite toggle.
struct AssetsSummaryCard: View {
    let accounts: [Account]
    let preferredCurrencyCode: String
    /// Latest cached FX rates. `nil` when the cache is empty and the
    /// network fetch failed — we then fall back to summing only
    /// same-currency items into the preferred-currency total.
    let fxSnapshot: FXRateSnapshot?
    let onEditAccount: (Account) -> Void
    /// Parent owns the actual deletion (SwiftData write + animation
    /// wrapping). The card only collects the user's intent.
    let onDeleteAccount: (Account) -> Void
    /// Parent flips `isFavorite` on the swiped account and clears it off
    /// the others — that exclusivity rule lives at the data layer, not
    /// inside this card.
    let onToggleFavorite: (Account) -> Void
    /// Opens the read-only deposit detail sheet for a savings account — its
    /// terms and its ledger history. Parent owns the sheet, like every other
    /// action here.
    let onShowDepositInfo: (Account) -> Void
    /// Raises the maturity prompt for a deposit that's owed a payout — the
    /// "ממתין לפדיון" badge's action. Matters most after the user has said
    /// "לא עכשיו" to the automatic prompt: without this the badge is a
    /// reminder with no way to act on it until the next launch.
    let onShowPayout: (Account) -> Void
    /// Opens the account editor in "new" mode. The card only signals the
    /// intent; `HomeView` owns the sheet and the SwiftData insert, exactly
    /// like the edit/delete/favourite handlers above.
    let onAddAccount: () -> Void
    /// How many accounts are currently soft-deleted. When > 0 the card
    /// shows a small "Recently Deleted" entry so they can be recovered.
    let deletedAccountCount: Int
    /// Opens the shared "Recently Deleted" screen. Parent owns the sheet.
    let onShowRecentlyDeleted: () -> Void

    /// Set when the user triggers the delete swipe. Drives the confirmation
    /// alert below — deleting an account is weighty enough (it pulls the
    /// account out of every total) to warrant a confirm, even though it's
    /// now recoverable. Never persists between renders, so `@State` is the
    /// right ownership.
    @State private var accountPendingDelete: Account?

    /// Whether the card is showing every account row or just the first few.
    /// Collapsed by default: the card is the top of the dashboard, and a
    /// user with a dozen accounts would otherwise push the budget card
    /// entirely off-screen. Session state, deliberately — coming back to
    /// the dashboard should give you the short card again.
    @State private var isExpanded: Bool = false

    /// How many account rows show before the rest collapse behind "הצג עוד".
    private static let collapsedRowLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader

            if accounts.isEmpty {
                Text("עדיין לא הוספת חשבונות.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                heroTotal
                separator
                accountRows
            }

            cardFooter
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .cardStyle()
        .alert(
            Text("מחיקת חשבון"),
            isPresented: deleteAlertBinding,
            presenting: accountPendingDelete
        ) { account in
            Button("מחיקה", role: .destructive) {
                onDeleteAccount(account)
            }
            Button("ביטול", role: .cancel) {}
        } message: { _ in
            Text("אפשר לשחזר את החשבון מ״נמחקו לאחרונה״ תוך 30 יום.")
        }
    }

    /// One footer row holding both small card-level actions: recovery on the
    /// visual right (leading, under RTL) and the expand/collapse toggle on
    /// the visual left. Kept as a single `HStack` so the card never grows two
    /// stacked footers, and skipped entirely when neither has anything to say.
    @ViewBuilder
    private var cardFooter: some View {
        if deletedAccountCount > 0 || hiddenAccountCount > 0 {
            HStack(spacing: Theme.Spacing.sm) {
                recentlyDeletedLink
                Spacer(minLength: Theme.Spacing.sm)
                expandToggle
            }
        }
    }

    /// Small footer entry into "Recently Deleted", shown only when there's
    /// at least one soft-deleted account to recover — so the card stays
    /// clean in the common case.
    @ViewBuilder
    private var recentlyDeletedLink: some View {
        if deletedAccountCount > 0 {
            Button(action: onShowRecentlyDeleted) {
                Label(
                    "נמחקו לאחרונה (\(deletedAccountCount))",
                    systemImage: "clock.arrow.circlepath"
                )
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
        }
    }

    /// Opens (and re-closes) the hidden account rows. Only drawn when rows
    /// are actually hidden — with three accounts or fewer the card already
    /// shows everything and the button would be noise.
    @ViewBuilder
    private var expandToggle: some View {
        if hiddenAccountCount > 0 {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                Label(
                    isExpanded ? "הצג פחות" : "הצג עוד",
                    systemImage: isExpanded ? "chevron.up" : "chevron.down"
                )
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.accent)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(isExpanded ? "סגירת שאר החשבונות" : "הצגת כל החשבונות"))
        }
    }

    /// How many rows the collapsed card is holding back. Drives both whether
    /// the toggle appears at all and the footer's existence.
    private var hiddenAccountCount: Int {
        max(0, accounts.count - Self.collapsedRowLimit)
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("הנכסים שלי")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)

            Spacer(minLength: Theme.Spacing.sm)

            // Text + icon (not an icon-only button) so VoiceOver reads a
            // real label and the action is discoverable in the empty state
            // too — the header shows whether or not there are accounts yet.
            Button("הוסף חשבון", systemImage: "plus.circle.fill", action: onAddAccount)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.accent)
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero

    /// One big number, rolled-up across every currency the user holds.
    /// When FX is unavailable the number falls back to the
    /// preferred-currency-only sum and the footer flips to a warning.
    private var heroTotal: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {

            Text(combinedTotal.formatted(.currency(code: preferredCurrencyCode)))
                .font(Theme.Typography.screenTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            fxFootnote
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// One-line note explaining where the headline number came from
    /// — either a converted total with a rate date, or a fallback
    /// message when FX is unavailable.
    @ViewBuilder
    private var fxFootnote: some View {
        if let snapshot = fxSnapshot {
            Text("מומר משערים של \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .omitted))")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        } else if hasCrossCurrencyHoldings {
            Text("שערי חליפין לא זמינים — מוצגת רק יתרה ב-\(preferredCurrencyCode).")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: 1)
    }

    // MARK: - Per-account rows

    /// We use a `List` (not a `VStack`) because `.swipeActions` is
    /// `List`-only. Every piece of `List` chrome — background,
    /// separators, default insets — is suppressed so the result looks
    /// like the previous vstack inside the card. Scrolling is disabled
    /// so the outer dashboard `ScrollView` stays the single scroller;
    /// height is sized to the row count to keep the embedded list
    /// from claiming all available space.
    private var accountRows: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    groupHeader(group)
                    rows(for: group.visibleAccounts)
                }
            }
        }
    }

    /// One group's account rows.
    ///
    /// A `List` per group, rather than one `List` with `Section`s: the list
    /// can't size itself here (it sits inside the dashboard's own scroll view
    /// with scrolling off), so its height has to be computed — and a row
    /// count times a row height is something we can compute exactly, while
    /// section-header heights are the system's business and guessing them
    /// clipped the last row. The headers therefore live outside, in the
    /// `VStack` above, where they're plain SwiftUI.
    private func rows(for accounts: [Account]) -> some View {
        List {
            ForEach(accounts) { account in
                // The row carries three separate taps — edit, pay out, and
                // "what is this deposit" — so the primary one is a *gesture*
                // rather than a `Button` wrapping the whole row. A button
                // nested inside another button's label fires both; a button
                // inside a plain view with its own tap gesture doesn't, since
                // the button claims its own bounds and the gesture takes the
                // rest. That's what lets the "ממתין לפדיון" badge stay beside
                // the account name, where it reads, instead of being exiled to
                // the trailing edge to keep it tappable.
                HStack(spacing: Theme.Spacing.xs) {
                    // Tap-to-edit, unified with the budget and transaction
                    // lists.
                    AccountSummaryRow(
                        account: account,
                        onPayoutTap: { onShowPayout(account) }
                    )
                    .contentShape(.rect)
                    .onTapGesture { onEditAccount(account) }
                    // `.onTapGesture` carries no button semantics of its own,
                    // so VoiceOver is told explicitly what the row is.
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text("הקש לעריכה"))

                    depositInfoButton(for: account)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: 0,
                    leading: 0,
                    bottom: Theme.Spacing.sm,
                    trailing: 0
                ))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    // Delete is the only trailing action now that editing
                    // moved to a row tap. Icon-only (an `Image`, not a
                    // `Label`) for a compact look that matches the other
                    // lists. Unlike the budget/transaction lists this one
                    // routes through a confirmation alert first — deleting
                    // an account is weightier — so the swipe sets the
                    // pending account rather than deleting outright.
                    Button(role: .destructive) {
                        accountPendingDelete = account
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(Text("מחיקה"))
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    // Leading edge = visual right under RTL — the side
                    // opposite delete, so favourite doesn't compete with
                    // the destructive action. Full swipe makes the common
                    // case ("make this my go-to") a single gesture.
                    //
                    // Absent for a deposit: it can't be the go-to account
                    // (`AccountType.allowsFavorite`), so offering the swipe
                    // would promise something the write path then refuses.
                    if account.canBeFavorite {
                        Button {
                            onToggleFavorite(account)
                        } label: {
                            Image(systemName: account.isFavorite ? "star.slash.fill" : "star.fill")
                        }
                        .tint(.yellow)
                        .accessibilityLabel(Text(account.isFavorite ? "ביטול מועדף" : "מועדף"))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        // Fixed per-row height so the embedded list sizes to content.
        // Tuned to fit the body+caption stack with breathing room; if
        // we add a third line to the row, bump this value to match.
        .frame(height: CGFloat(accounts.count) * Self.estimatedRowHeight)
    }

    /// The little "i" beside a deposit row, opening its detail sheet.
    /// Deposits only: it's the one account type with terms and a payout story
    /// worth reading, and every row carrying one would just add noise.
    @ViewBuilder
    private func depositInfoButton(for account: Account) -> some View {
        if account.isDeposit {
            Button {
                onShowDepositInfo(account)
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    // A bigger tap target than the glyph, without the glyph
                    // itself growing and unbalancing the row.
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("פרטי הפיקדון"))
        }
    }

    /// A group's name and its own subtotal, converted into the preferred
    /// currency like the hero above — so "how much can I actually spend" is
    /// answerable without adding the rows up by eye.
    private func groupHeader(_ group: AccountGroup) -> some View {
        HStack {
            Text(group.title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textCase(.uppercase)
            Spacer(minLength: Theme.Spacing.sm)
            Text(total(of: group.accounts).formatted(.currency(code: preferredCurrencyCode)))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }

    private static let estimatedRowHeight: CGFloat = 56

    // MARK: - Grouping

    /// The dashboard's two buckets: money you can spend today, and money
    /// that's tied up. Accounts land on one side or the other via
    /// `AccountType.isLiquid`.
    private struct AccountGroup: Identifiable {
        let id: String
        let title: LocalizedStringKey
        /// Every account in the group — what the header's subtotal sums.
        let accounts: [Account]
        /// The subset actually drawn as rows. Equal to `accounts` when the
        /// card is expanded; a prefix of it when collapsed.
        let visibleAccounts: [Account]
    }

    /// Liquid first, then assets; empty groups are dropped so a user with
    /// only an עו״ש sees one plain list rather than an empty heading.
    ///
    /// Collapsing trims *rows*, never maths: each group keeps its full
    /// `accounts` for the subtotal in the header while `visibleAccounts`
    /// takes from a shared row budget, spent in display order. That way
    /// "3 rows" means three rows on the card rather than three per group,
    /// and the numbers on screen still add up to the hero total.
    private var groups: [AccountGroup] {
        let sorted = sortedAccounts
        var budget = isExpanded ? sorted.count : Self.collapsedRowLimit

        func group(id: String, title: LocalizedStringKey, accounts: [Account]) -> AccountGroup? {
            let shown = min(accounts.count, budget)
            guard shown > 0 else { return nil }
            budget -= shown
            return AccountGroup(
                id: id,
                title: title,
                accounts: accounts,
                visibleAccounts: Array(accounts.prefix(shown))
            )
        }

        return [
            group(id: "liquid", title: "נזיל", accounts: sorted.filter { $0.type.isLiquid }),
            group(id: "assets", title: "נכסים", accounts: sorted.filter { !$0.type.isLiquid })
        ].compactMap { $0 }
    }

    // MARK: - Alert plumbing

    /// `.alert(presenting:)` needs a `Binding<Bool>` for `isPresented`;
    /// bridge it through the optional pending account so the dismiss path
    /// clears it in one place.
    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { accountPendingDelete != nil },
            set: { if !$0 { accountPendingDelete = nil } }
        )
    }

    // MARK: - Row ordering

    /// The order accounts appear in the list: the favourite floats to the
    /// top, then everything else groups by account type (everyday → savings
    /// → investment → catch-all), and finally sorts by name within each
    /// group so the order stays stable as balances change.
    ///
    /// Only the *visible rows* are sorted — `combinedTotal` and the FX
    /// check below iterate the raw `accounts`, since order is irrelevant
    /// to a sum.
    private var sortedAccounts: [Account] {
        accounts.sorted { lhs, rhs in
            // Favourite first, regardless of its type.
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            // Then by the fixed type order.
            let lRank = lhs.type.sortRank
            let rRank = rhs.type.sortRank
            if lRank != rRank { return lRank < rRank }
            // Stable, predictable tiebreak within a group.
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Computed data

    /// Sum every account's balance and every holding's market value,
    /// converting each into the preferred currency. When FX is
    /// unavailable, items in non-preferred currencies are skipped.
    private var combinedTotal: Decimal { total(of: accounts) }

    /// Sum of a set of accounts — balance plus any holdings — converted into
    /// the preferred currency. Used for both the hero and the per-group
    /// subtotals, so the parts always add up to the whole.
    private func total(of accounts: [Account]) -> Decimal {
        var total = Decimal(0)
        for account in accounts {
            total += convertToPreferred(account.balance, from: account.currencyCode)
            for holding in account.holdings {
                total += convertToPreferred(holding.marketValue, from: holding.currencyCode)
            }
        }
        return total
    }

    private func convertToPreferred(_ amount: Decimal, from currency: String) -> Decimal {
        if currency == preferredCurrencyCode { return amount }
        guard let snapshot = fxSnapshot,
              let converted = CurrencyConverter.convert(
                amount,
                from: currency,
                to: preferredCurrencyCode,
                using: snapshot
              ) else {
            // Drop the line: better an under-count than a wrong number.
            return 0
        }
        return converted
    }

    /// Used to decide whether the "FX unavailable" warning is even
    /// meaningful. If every account is in the preferred currency, we
    /// don't need to mention FX at all.
    private var hasCrossCurrencyHoldings: Bool {
        for account in accounts {
            if account.currencyCode != preferredCurrencyCode { return true }
            for holding in account.holdings where holding.currencyCode != preferredCurrencyCode {
                return true
            }
        }
        return false
    }
}

/// One account row — icon, name, total. The total is in the
/// *account's own* currency: this is the per-account read, separate
/// from the unified hero above. Tapping the row edits the account;
/// delete and favourite are the trailing/leading swipe actions wired
/// up by the parent.
private struct AccountSummaryRow: View {
    let account: Account
    /// Tapped on the "ממתין לפדיון" badge. Only ever reachable when the badge
    /// is drawn, i.e. when the deposit is actually owed a payout.
    let onPayoutTap: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: account.type.symbolName)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(account.name.isEmpty ? "ללא שם" : account.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if account.isFavorite && account.canBeFavorite {
                        // Tiny inline star so the favourite is visible
                        // at a glance without opening the editor. Gated on
                        // `canBeFavorite` as well as the flag so a deposit
                        // starred before the rule existed stops drawing one
                        // even before the store has been healed.
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.yellow)
                            .accessibilityLabel(Text("חשבון מועדף"))
                    }

                    pendingPayoutBadge
                }
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: Theme.Spacing.sm)

            // Long balances (e.g. high-value investment accounts) must
            // stay on one line and shrink to fit instead of wrapping.
            Text(displayTotal.formatted(.currency(code: account.currencyCode)))
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
        }
    }

    /// "Waiting to be paid out" — shown once a deposit has passed its
    /// maturity date with the money still sitting in it.
    ///
    /// Not conditioned on `autoPayoutOnMaturity`: a deposit set to transfer
    /// automatically is settled by `HomeView.settleMaturedDeposits` as soon as
    /// the dashboard appears, so it simply isn't in this state by the time
    /// anyone reads the row. When one *does* linger — its payout account was
    /// deleted, or two currencies with no FX rate to bridge them — it needs
    /// the user's attention more than a manual one does, not less.
    /// Tappable: it opens the maturity prompt, so the reminder and the way to
    /// act on it are the same control. `.plain` keeps the capsule's own
    /// styling instead of taking a system tint, and the chevron marks it as
    /// something to press rather than just a status colour.
    @ViewBuilder
    private var pendingPayoutBadge: some View {
        if account.isAwaitingPayout() {
            Button(action: onPayoutTap) {
                HStack(spacing: 2) {
                    Text("ממתין לפדיון")
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(Theme.Typography.captionSmall)
                .foregroundStyle(Theme.Colors.wants)
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 2)
                .background(Theme.Colors.wants.opacity(0.15), in: Capsule())
                .contentShape(Capsule())
                .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("הקש להעברת הכסף"))
        }
    }

    /// Same-currency total — balance plus holdings denominated in the
    /// account's own currency. Cross-currency holdings are *not*
    /// rolled into this row's number; they're counted in the hero
    /// above instead. Keeps the row honest: this is "what the bank
    /// would show you", in one currency.
    private var displayTotal: Decimal {
        var total = account.balance
        if account.type == .investment {
            for holding in account.holdings where holding.currencyCode == account.currencyCode {
                total += holding.marketValue
            }
        }
        return total
    }

    private var subtitle: String {
        if account.type == .investment, !account.holdings.isEmpty {
            // `String(localized:)` so the count gets proper Hebrew plurals
            // (נכס אחד / שני נכסים / N נכסים) from the catalog.
            let holdings = String(localized: "\(account.holdings.count) נכסים")
            return "\(account.type.hebrewLabel) • \(holdings)"
        }
        if let depositDetail {
            return "\(account.type.hebrewLabel) • \(depositDetail)"
        }
        return account.type.hebrewLabel
    }

    /// The deposit's terms in a few words: its rate, and either when it
    /// matures or that it already has. `nil` for anything that isn't a
    /// deposit — a plain savings pot keeps the bare type label.
    private var depositDetail: String? {
        guard let terms = account.depositTerms else { return nil }

        var parts: [String] = []
        if let rate = terms.annualRatePercent, rate > 0 {
            parts.append("\(rate.formatted(.number.precision(.fractionLength(0...2))))%")
        }
        // How many separate deposits are laddered inside. Only said once there
        // is more than one — "הפקדה אחת" on an ordinary deposit is noise.
        let depositCount = account.depositCount
        if account.isReplenishable, depositCount > 1 {
            // `String(localized:)` so the count pluralises properly in Hebrew
            // (הפקדה אחת / שתי הפקדות / N הפקדות) via the catalog.
            parts.append(String(localized: "\(depositCount) הפקדות"))
        }
        if account.payoutCompletedAt != nil {
            parts.append("נפדה")
        } else if account.isAwaitingPayout() {
            // Nothing: the "ממתין לפדיון" badge beside the name already says
            // this, and repeating it in the subtitle read as two separate
            // facts about the same deposit.
        } else if let maturity = account.effectiveMaturityDate {
            // Numeric, not abbreviated: the row subtitle is one line, and
            // "עד 13 במרץ 2028" ran past it where "עד 13.3.2028" fits.
            parts.append("עד \(maturity.formatted(date: .numeric, time: .omitted))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        AssetsSummaryCard(
            accounts: [],
            preferredCurrencyCode: "ILS",
            fxSnapshot: nil,
            onEditAccount: { _ in },
            onDeleteAccount: { _ in },
            onToggleFavorite: { _ in },
            onShowDepositInfo: { _ in },
            onShowPayout: { _ in },
            onAddAccount: {},
            deletedAccountCount: 0,
            onShowRecentlyDeleted: {}
        )
        .padding(Theme.Spacing.lg)
    }
}
