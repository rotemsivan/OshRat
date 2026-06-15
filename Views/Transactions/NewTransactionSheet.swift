import SwiftUI
import SwiftData

/// "תנועה חדשה" — the modal sheet for adding a new income, expense, or
/// (later) account-to-account transfer.
///
/// Top to bottom:
///   1. **Segmented picker** — הכנסה / הוצאה / העברה בין חשבונות. The
///      transfer option is wired but disabled for now (shows a "בקרוב"
///      placeholder); the income/expense flow is fully functional.
///   2. **Accounts** — one picker for income/expense (pre-selected to
///      the user's favourite account), two pickers for transfers.
///   3. **Category** — same list as the budget builder, filtered to the
///      side that matches the selected kind. Transfers don't take one.
///   4. **Title** — short headline ("שם התנועה").
///   5. **Details** — long-form note.
///   6. **Amount** — large `BigAmountField` with the user's preferred
///      currency as the trailing label.
///   7. **Slide-to-confirm** — replaces a "save" button so the act of
///      committing money feels deliberate. Snaps into a checkmark when
///      the user crosses the threshold, then dismisses the sheet.
///
/// Side input flows in (`onSave` callback) so the parent can run a
/// quick haptic / toast if it wants to celebrate. The sheet inserts
/// the SwiftData row itself so a future "edit transaction" sheet can
/// reuse the same body without rewiring the save path.
struct NewTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query private var profiles: [UserProfile]
    /// Newest snapshot first; the head of the array is the freshest FX
    /// snapshot we have. Used to convert when the transaction's currency
    /// differs from the account's currency.
    @Query(sort: \FXRateSnapshot.fetchedAt, order: .reverse) private var fxSnapshots: [FXRateSnapshot]

    /// Currencies the user can pick for the transaction amount. Kept in
    /// sync with `AccountEditorSheet.supportedCurrencies` — if you add
    /// one there, add it here too.
    private let supportedCurrencies: [String] = ["ILS", "USD", "EUR"]

    /// Optional ping for the parent ("a new transaction was saved").
    /// The sheet handles the SwiftData insert internally — this is just
    /// so callers can react (e.g. haptic, confetti) without re-querying.
    let onSaved: ((Transaction) -> Void)?

    // MARK: - Form state

    @State private var kind: SheetKind = .expense
    @State private var sourceAccount: Account?
    @State private var destinationAccount: Account?
    @State private var category: Category?
    @State private var title: String = ""
    @State private var details: String = ""
    @State private var amount: Decimal = 0
    /// Currency the user is typing the amount in. Starts as the source
    /// account's currency (so the common case is zero-conversion) but
    /// can diverge — the confirm path then converts via the cached FX
    /// snapshot before touching the account balance.
    @State private var amountCurrencyCode: String = "ILS"
    /// The body slides/fades in with a tiny stagger when the sheet
    /// first appears — sets to `true` in `.onAppear`.
    @State private var hasAppeared: Bool = false

    init(onSaved: ((Transaction) -> Void)? = nil) {
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        kindPickerSection
                            .appearStagger(index: 0, visible: hasAppeared)

                        if kind == .transfer {
                            transferComingSoon
                                .appearStagger(index: 1, visible: hasAppeared)
                        } else {
                            accountSection
                                .appearStagger(index: 1, visible: hasAppeared)
                            categorySection
                                .appearStagger(index: 2, visible: hasAppeared)
                            titleSection
                                .appearStagger(index: 3, visible: hasAppeared)
                            detailsSection
                                .appearStagger(index: 4, visible: hasAppeared)
                            amountSection
                                .appearStagger(index: 5, visible: hasAppeared)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.xl + 80) // breathing room above the slide bar
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom) {
                SlideToConfirm(
                    label: confirmLabel,
                    isEnabled: canConfirm,
                    onConfirm: handleConfirm
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
            }
            .font(Theme.Typography.body)
            .navigationTitle(Text("תנועה חדשה"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                }
            }
        }
        .tint(Theme.Colors.accent)
        // The app is Hebrew-only, but the sheet is composed of custom
        // VStack/HStack/TextField — not Form — so we don't get the
        // automatic Form-driven mirroring some other screens lean on.
        // Forcing the layout direction here pins placeholders, picker
        // rows, and section labels to a consistent RTL layout no
        // matter what the simulator locale happens to be.
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            primeDefaults()
            // Slight delay so the spring entrance reads as motion rather
            // than a flash. The staggered modifier inside each section
            // then layers small offsets on top.
            withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(0.05)) {
                hasAppeared = true
            }
        }
        .onChange(of: kind) { _, new in
            // When switching to a side where the current category no
            // longer fits (income → expense or vice versa), drop it so
            // we never persist a mismatched (kind, category) pair.
            if let c = category, c.kind.rawValue != new.transactionKind?.rawValue {
                category = nil
            }
        }
        .onChange(of: sourceAccount) { _, new in
            // When the user switches accounts, snap the amount currency
            // to the new account's currency. Avoids the silent surprise
            // of typing 50 in "USD" while the new account is ILS.
            if let account = new {
                amountCurrencyCode = account.currencyCode
            }
        }
    }

    // MARK: - Sections

    private var kindPickerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("סוג")
            Picker("סוג", selection: $kind) {
                ForEach(SheetKind.allCases) { k in
                    Text(k.hebrewLabel).tag(k)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    /// Placeholder for the not-yet-built transfer flow. Leaves the
    /// picker option visible so the surface area of the feature is
    /// discoverable, but blocks confirmation.
    private var transferComingSoon: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.accent.opacity(0.6))
            Text("העברה בין חשבונות תיתמך בקרוב")
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("נרכז כאן בקרוב את ההעברות הפנימיות בין החשבונות שלך — כך שלא יתחלפו עם הכנסות והוצאות.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel(kind == .income ? "לאיזה חשבון להוסיף" : "מאיזה חשבון")
            Menu {
                ForEach(selectableAccounts) { account in
                    Button {
                        sourceAccount = account
                    } label: {
                        Label {
                            Text(account.name)
                            if account.isFavorite {
                                Text("(מועדף)")
                            }
                        } icon: {
                            Image(systemName: account.isFavorite ? "star.fill" : "circle")
                        }
                    }
                }
            } label: {
                pickerRow(text: sourceAccount?.name ?? "בחרו חשבון")
            }
        }
    }

    /// Accounts the user may pick as source for an income or expense.
    /// Savings and investment accounts are deliberately excluded: those
    /// move money via the dedicated "העברה בין חשבונות" flow, not as
    /// income / expense rows. Filtering here (rather than disabling at
    /// confirm time) keeps the picker honest — the user only sees
    /// options that will actually save.
    private var selectableAccounts: [Account] {
        accounts.filter { $0.type == .current }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("קטגוריה")
            Menu {
                ForEach(filteredCategories) { c in
                    Button {
                        category = c
                    } label: {
                        Label(c.name, systemImage: c.symbolName)
                    }
                }
            } label: {
                pickerRow(text: category?.name ?? "בחרו קטגוריה")
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("שם התנועה")
            HebrewTextField("למשל: קניות בסופר", text: $title)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.Colors.separator, lineWidth: 1)
                )
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("פרטים נוספים")
            HebrewTextEditor("לא חובה — מקום לפירוט", text: $details, minHeight: 60)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(Theme.Colors.separator, lineWidth: 1)
                )
                .frame(alignment: .leading)
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("סכום")
            BigAmountField(
                value: $amount,
                currencyCode: $amountCurrencyCode,
                supportedCurrencies: supportedCurrencies
            )
            if let preview = conversionPreviewText {
                Text(preview)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Small helpers

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .textCase(.uppercase)
            // `.leading` resolves to the visual right edge under RTL,
            // which is where the eye lands first in Hebrew. Earlier we
            // used `.trailing`, which mirrored to the visual left and
            // read as a stray label floating away from its field.
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Picker label row — Hebrew value text on the visual right,
    /// chevron on the visual left.
    ///
    /// Implementation note: `Menu { ... } label: { ... }` doesn't
    /// reliably forward the `\.layoutDirection` environment into the
    /// label closure, so even with RTL forced on the sheet root the
    /// row kept rendering LTR. We pin direction directly on the row
    /// AND swap the children to their RTL-correct visual positions
    /// (text leading, chevron trailing) so the layout is correct
    /// whether or not the environment propagates.
    private func pickerRow(text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Colors.separator, lineWidth: 1)
        )
        .environment(\.layoutDirection, .rightToLeft)
    }

    // MARK: - Derived state

    /// Categories filtered to the side the user picked. Income shows
    /// only income categories, expense shows only expense ones — keeps
    /// the menu short and prevents accidental mismatches at save time.
    /// `semanticallyUnique` collapses any leftover duplicate rows so
    /// the picker never visually doubles up.
    private var filteredCategories: [Category] {
        switch kind {
        case .income:  return categories.filter { $0.kind == .income }.semanticallyUnique
        case .expense: return categories.filter { $0.kind == .expense }.semanticallyUnique
        case .transfer: return []
        }
    }

    private var preferredCurrencyCode: String {
        profiles.first?.preferredCurrencyCode ?? "ILS"
    }

    /// Returns the amount converted into the source account's currency,
    /// or `nil` if conversion is impossible (cross-currency without an
    /// FX snapshot, or a code that the snapshot doesn't cover). Used in
    /// both the confirm path (to apply the balance change) and the
    /// preview line under the picker.
    private func amountInAccountCurrency(_ raw: Decimal, _ account: Account) -> Decimal? {
        if amountCurrencyCode == account.currencyCode { return raw }
        guard let snapshot = fxSnapshots.first else { return nil }
        return CurrencyConverter.convert(
            raw,
            from: amountCurrencyCode,
            to: account.currencyCode,
            using: snapshot
        )
    }

    /// Single-line "≈ X.XX ACC" hint shown below the currency picker
    /// when the user types in a currency that isn't the account's own.
    /// Nil when no conversion is needed (same currency) or when it's
    /// impossible (no FX snapshot) — the latter is surfaced by the
    /// disabled confirm slider instead.
    private var conversionPreviewText: String? {
        guard let account = sourceAccount,
              amountCurrencyCode != account.currencyCode,
              amount > 0
        else { return nil }
        if let converted = amountInAccountCurrency(amount, account) {
            return "≈ \(converted.formatted(.currency(code: account.currencyCode)))"
        }
        // FX snapshot missing or doesn't cover this pair — tell the
        // user why the slider is disabled.
        return "שערי חליפין לא זמינים — לא ניתן להמיר ל-\(account.currencyCode)."
    }

    private var canConfirm: Bool {
        guard kind != .transfer else { return false }
        guard let account = sourceAccount else { return false }
        // Block confirm when the amount can't be expressed in the
        // account's currency — otherwise the balance update would
        // silently skip and the row would look like it landed but
        // the balance wouldn't move.
        guard amountInAccountCurrency(amount, account) != nil else { return false }
        return category != nil
            && amount > 0
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var confirmLabel: String {
        switch kind {
        case .income:   return "החליקו להוספת הכנסה"
        case .expense:  return "החליקו להוספת הוצאה"
        case .transfer: return "בקרוב — העברה בין חשבונות"
        }
    }

    // MARK: - Behaviour

    /// Pick sensible defaults on first appearance so the user only has
    /// to fill in what's specific to this transaction. The favourite
    /// account becomes the source, falling back to the first account.
    /// The amount currency is seeded from that account so the common
    /// case avoids any FX conversion.
    private func primeDefaults() {
        if sourceAccount == nil {
            // Only current accounts are valid for income/expense, so the
            // default lookup honours that — a favourite savings account
            // shouldn't quietly become the seed for an expense.
            let pool = selectableAccounts
            sourceAccount = pool.first(where: { $0.isFavorite }) ?? pool.first
        }
        if let account = sourceAccount {
            amountCurrencyCode = account.currencyCode
        } else {
            amountCurrencyCode = preferredCurrencyCode
        }
    }

    private func handleConfirm() {
        guard canConfirm,
              let account = sourceAccount,
              let kindModel = kind.transactionKind,
              let accountAmount = amountInAccountCurrency(amount, account)
        else { return }

        // Roll the balance with the transaction in the account's own
        // currency: income adds, expense subtracts. `accountAmount` is
        // already converted if the user typed a different currency.
        switch kindModel {
        case .income:  account.balance += accountAmount
        case .expense: account.balance -= accountAmount
        }
        account.lastUpdated = .now

        // The transaction keeps the *original* amount and currency the
        // user typed, so foreign-currency rows still read as such in
        // the history. `balanceAfter` snapshots the resulting account
        // balance so the row can show the running balance the user
        // actually saw at the moment of entry.
        let transaction = Transaction(
            amount: amount,
            kind: kindModel,
            date: .now,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: details.trimmingCharacters(in: .whitespacesAndNewlines),
            currencyCode: amountCurrencyCode,
            balanceAfter: account.balance,
            category: category,
            account: account
        )
        modelContext.insert(transaction)
        try? modelContext.save()
        onSaved?(transaction)

        // Tiny delay lets the user see the checkmark snap in before the
        // sheet slides away — without it the dismissal masks the cue.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            dismiss()
        }
    }
}

// MARK: - Sheet-local kind

/// The three options shown in the segmented picker. Stored separately
/// from `TransactionKind` so the sheet can model "transfer" without
/// polluting the persistence-level enum (which is only income/expense
/// for now — see CLAUDE.md). When transfer is implemented later this
/// will map either to a new `TransactionKind.transfer` case or to a
/// paired-transaction strategy.
enum SheetKind: String, CaseIterable, Identifiable {
    case income
    case expense
    case transfer

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .income:   return "הכנסה"
        case .expense:  return "הוצאה"
        case .transfer: return "העברה בין חשבונות"
        }
    }

    /// Bridge to the persistence-level enum. Nil for transfer since the
    /// persistence model doesn't represent that case yet.
    var transactionKind: TransactionKind? {
        switch self {
        case .income:   return .income
        case .expense:  return .expense
        case .transfer: return nil
        }
    }
}

// MARK: - Staggered appearance modifier

/// Adds a small fade + slide-in delay per section so the sheet body
/// reads as a single staggered motion instead of a hard cut. Index is
/// 0-based; each step adds ~60ms of delay.
private struct AppearStagger: ViewModifier {
    let index: Int
    let visible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 12)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.85)
                    .delay(Double(index) * 0.06),
                value: visible
            )
    }
}

private extension View {
    func appearStagger(index: Int, visible: Bool) -> some View {
        modifier(AppearStagger(index: index, visible: visible))
    }
}

#Preview {
    NewTransactionSheet(onSaved: nil)
        .modelContainer(
            for: [
                UserProfile.self, Account.self, Holding.self, Category.self,
                Transaction.self, BudgetItem.self, Goal.self, FXRateSnapshot.self
            ],
            inMemory: true
        )
}
