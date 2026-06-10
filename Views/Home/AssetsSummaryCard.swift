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
/// Each account row supports two swipe actions on the trailing edge:
///   * **עריכה** — opens the same `AccountEditorSheet` as the pencil
///   * **מחיקה** — pops a confirmation alert; on confirm, the parent
///     deletes via SwiftData inside a `withAnimation` block so the
///     row collapses smoothly.
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

    /// Set when the user taps "מחיקה" on a swipe action. Drives the
    /// confirmation alert below — never persists between renders, so
    /// `@State` (not `@Binding`) is the right ownership.
    @State private var accountPendingDelete: Account?

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
            Text("אתה בטוח שברצונך למחוק את החשבון?")
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        Text("הנכסים שלי")
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        List {
            ForEach(accounts) { account in
                AccountSummaryRow(account: account)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: 0,
                        bottom: Theme.Spacing.sm,
                        trailing: 0
                    ))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // Order matters: SwiftUI lays the first item out
                    // closest to the swipe edge. Putting Delete first
                    // means it sits at the trailing edge — the
                    // "destructive" position users expect.
                    Button(role: .destructive) {
                        accountPendingDelete = account
                    } label: {
                        Label("מחיקה", systemImage: "trash")
                    }

                    Button {
                        onEditAccount(account)
                    } label: {
                        Label("עריכה", systemImage: "pencil")
                    }
                    .tint(Theme.Colors.accent)
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

    private static let estimatedRowHeight: CGFloat = 56

    // MARK: - Alert plumbing

    /// `.alert(presenting:)` needs a `Binding<Bool>` for `isPresented`;
    /// we bridge it through the optional `accountPendingDelete` so the
    /// "dismiss" path clears the pending account in one place.
    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { accountPendingDelete != nil },
            set: { if !$0 { accountPendingDelete = nil } }
        )
    }

    // MARK: - Computed data

    /// Sum every account's balance and every holding's market value,
    /// converting each into the preferred currency. When FX is
    /// unavailable, items in non-preferred currencies are skipped.
    private var combinedTotal: Decimal {
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
/// from the unified hero above. Edit and delete are reached via the
/// trailing swipe actions wired up by the parent.
private struct AccountSummaryRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbolName)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name.isEmpty ? "ללא שם" : account.name)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
            return "\(account.type.hebrewLabel) • \(account.holdings.count) נכסים"
        }
        return account.type.hebrewLabel
    }

    private var symbolName: String {
        switch account.type {
        case .current:    return "banknote"
        case .savings:    return "lock"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .other:      return "circle.dashed"
        }
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
            onDeleteAccount: { _ in }
        )
        .padding(Theme.Spacing.lg)
    }
}
