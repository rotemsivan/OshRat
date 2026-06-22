import SwiftUI
import SwiftData

/// "תנועה חדשה" — the modal sheet for adding a new income, expense, or
/// account-to-account transfer.
///
/// Top to bottom:
///   1. **Segmented picker** — הכנסה / הוצאה / העברה בין חשבונות. All
///      three flows are functional; switching kind animates the form
///      between the income/expense layout and the transfer layout.
///   2. **Accounts** — one picker for income/expense (pre-selected to
///      the user's favourite account); for transfers, an animated
///      source → destination diagram with a picker on each side.
///   3. **Category** — same list as the budget builder, filtered to the
///      side that matches the selected kind. Transfers don't take one.
///   4. **Title** — short headline ("שם התנועה").
///   5. **Details** — long-form note (income/expense only).
///   6. **Amount** — large `BigAmountField` with the user's preferred
///      currency as the trailing label. For a transfer the currency is
///      locked to the source account (what leaves it), and a preview
///      shows what the destination receives after FX conversion.
///   7. **Slide-to-confirm** — replaces a "save" button so the act of
///      committing money feels deliberate. Tinted per kind; snaps into a
///      checkmark when the user crosses the threshold, fires a themed
///      glow, then dismisses the sheet.
///
/// Side input flows in (`onSave` callback) so the parent can run a
/// quick haptic / toast if it wants to celebrate. The sheet inserts
/// the SwiftData row itself so a future "edit transaction" sheet can
/// reuse the same body without rewiring the save path.
struct NewTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    /// Decorative motion (the flowing transfer arrow, the kind-switch
    /// transition, the post-confirm glow pulse) is softened or dropped
    /// when the user has Reduce Motion on.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// The transaction being edited, or `nil` for a brand-new entry.
    /// When set, the sheet opens pre-filled from this row and the
    /// confirm path *updates* it (reversing its old balance effect and
    /// applying the new one) instead of inserting a fresh row.
    private let editingTransaction: Transaction?

    /// Optional ping for the parent ("a transaction was saved"). The
    /// sheet handles the SwiftData insert/update internally — this is
    /// just so callers can react (e.g. haptic, confetti) without
    /// re-querying.
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
    /// Flips to `true` the instant the slide-to-confirm crosses its
    /// threshold, driving the themed glow that flashes over the sheet
    /// (coloured by `kind`) just before it dismisses.
    @State private var hasConfirmed: Bool = false

    /// - Parameters:
    ///   - transaction: an existing row to edit, or `nil` to add a new
    ///     one. In edit mode every form field is seeded from the row via
    ///     `State(initialValue:)` so the sheet opens pre-filled.
    ///   - onSaved: optional callback fired after the save lands.
    init(transaction: Transaction? = nil, onSaved: ((Transaction) -> Void)? = nil) {
        self.editingTransaction = transaction
        self.onSaved = onSaved

        if let transaction {
            _kind = State(initialValue: SheetKind(transaction.kind))
            _sourceAccount = State(initialValue: transaction.account)
            _category = State(initialValue: transaction.category)
            _title = State(initialValue: transaction.title)
            _details = State(initialValue: transaction.note)
            _amount = State(initialValue: transaction.amount)
            _amountCurrencyCode = State(initialValue: transaction.currencyCode)
        }
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
                            transferSection
                                .appearStagger(index: 1, visible: hasAppeared)
                                .transition(kindTransition)
                            amountSection
                                .appearStagger(index: 2, visible: hasAppeared)
                                .transition(kindTransition)
                            titleSection
                                .appearStagger(index: 3, visible: hasAppeared)
                                .transition(kindTransition)
                        } else {
                            accountSection
                                .appearStagger(index: 1, visible: hasAppeared)
                                .transition(kindTransition)
                            categorySection
                                .appearStagger(index: 2, visible: hasAppeared)
                                .transition(kindTransition)
                            titleSection
                                .appearStagger(index: 3, visible: hasAppeared)
                                .transition(kindTransition)
                            detailsSection
                                .appearStagger(index: 4, visible: hasAppeared)
                                .transition(kindTransition)
                            amountSection
                                .appearStagger(index: 5, visible: hasAppeared)
                                .transition(kindTransition)
                        }
                    }
                    // Animate the swap between the income/expense layout and
                    // the transfer layout. Reduce Motion users get an
                    // instant cut (the `kindTransition` collapses to
                    // `.identity` and we pass `nil` here).
                    .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: kind)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.xl + 80) // breathing room above the slide bar
                }
                .scrollIndicators(.hidden)
            }
            // Themed glow that flashes from the bottom (where the slider
            // lives) once the user confirms — green for income, red for
            // expense, accent for a transfer.
            .overlay(alignment: .bottom) { confirmGlow }
            .safeAreaInset(edge: .bottom) {
                SlideToConfirm(
                    label: confirmLabel,
                    isEnabled: canConfirm,
                    tint: kindTint,
                    onConfirm: handleConfirm
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
            }
            .font(Theme.Typography.body)
            .navigationTitle(editingTransaction == nil ? Text("תנועה חדשה") : Text("עריכת תנועה"))
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
            // Only seed defaults for a *new* transaction. In edit mode the
            // form is already populated from the row in `init`, and
            // re-priming would clobber the user's chosen account/currency.
            if editingTransaction == nil {
                primeDefaults()
            }
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
            if new == .transfer {
                // The transfer amount is locked to the source's currency,
                // so pin it now (the user may have typed in another
                // currency while in expense mode), and seed a destination
                // that isn't the source.
                if let source = sourceAccount {
                    amountCurrencyCode = source.currencyCode
                }
                if destinationAccount == nil
                    || destinationAccount?.persistentModelID == sourceAccount?.persistentModelID {
                    destinationAccount = transferAccounts.first {
                        $0.persistentModelID != sourceAccount?.persistentModelID
                    }
                }
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

    /// Animated "source → destination" transfer picker. A chip on each
    /// side (tap to choose its account) with a flowing arrow between them.
    /// Any account type is selectable here — unlike income/expense, a
    /// transfer is exactly how money reaches savings / investment accounts.
    private var transferSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sectionLabel("העברה בין חשבונות")
            HStack(spacing: Theme.Spacing.xs) {
                // Source first → lands on the visual right under RTL; the
                // arrow then flows leftward toward the destination chip.
                accountChip(
                    caption: "מהחשבון",
                    account: sourceAccount,
                    excluding: destinationAccount
                ) { sourceAccount = $0 }

                TransferFlowArrow(animated: !reduceMotion)

                accountChip(
                    caption: "לחשבון",
                    account: destinationAccount,
                    excluding: sourceAccount
                ) { destinationAccount = $0 }
            }
        }
    }

    /// One side of the transfer diagram: a tappable chip showing the
    /// chosen account (type icon + name + currency) or a "choose" prompt.
    /// `excluding` is the account already picked on the other side — hidden
    /// from this menu so a transfer can't have the same account on both
    /// ends. A spring on the selection makes a freshly-picked account pop.
    private func accountChip(
        caption: LocalizedStringKey,
        account: Account?,
        excluding other: Account?,
        onPick: @escaping (Account) -> Void
    ) -> some View {
        Menu {
            ForEach(transferAccounts.filter { $0.persistentModelID != other?.persistentModelID }) { option in
                Button {
                    onPick(option)
                } label: {
                    Label(option.name, systemImage: accountSymbol(option.type))
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(caption)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: account.map { accountSymbol($0.type) } ?? "circle.dashed")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                    Text(account?.name ?? "בחרו חשבון")
                        .font(Theme.Typography.body)
                        .foregroundStyle(account == nil ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                        .lineLimit(1)
                }
                Text(account?.currencyCode ?? " ")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(account == nil ? Theme.Colors.separator : Theme.Colors.accent.opacity(0.45), lineWidth: 1)
            )
            .environment(\.layoutDirection, .rightToLeft)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: account?.persistentModelID)
    }

    /// SF Symbol per account type. Mirrors `AnalyticsReport.symbol(for:)`
    /// so an account reads with the same icon wherever it appears.
    private func accountSymbol(_ type: AccountType) -> String {
        switch type {
        case .current:       return "banknote"
        case .digitalWallet: return "wallet.bifold"
        case .savings:       return "lock"
        case .investment:    return "chart.line.uptrend.xyaxis"
        }
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

    /// Endpoints offered for a transfer: *every* account, regardless of
    /// type. Moving money into a savings or investment account is the
    /// whole point of the transfer flow, so the current-only restriction
    /// that income/expense uses deliberately doesn't apply here.
    private var transferAccounts: [Account] {
        accounts
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
            sectionLabel(kind == .transfer ? "סכום להעברה" : "סכום")
            BigAmountField(
                value: $amount,
                currencyCode: $amountCurrencyCode,
                supportedCurrencies: supportedCurrencies,
                // For a transfer the amount is what leaves the *source*, so
                // its currency is pinned to the source account; the
                // destination figure is derived below via FX.
                isCurrencyLocked: kind == .transfer
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
        if kind == .transfer { return transferPreviewText }
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

    /// Amount the destination account receives, in *its own* currency.
    /// For a same-currency transfer that's just `amount`; otherwise it's
    /// the FX conversion via the latest snapshot, or `nil` when no rate
    /// bridges the two currencies — which disables the confirm slider.
    /// (`amountCurrencyCode` is locked to the source in transfer mode, so
    /// this converts source → destination.)
    private var transferDestAmount: Decimal? {
        guard let destination = destinationAccount else { return nil }
        if amountCurrencyCode == destination.currencyCode { return amount }
        guard let snapshot = fxSnapshots.first else { return nil }
        return CurrencyConverter.convert(
            amount,
            from: amountCurrencyCode,
            to: destination.currencyCode,
            using: snapshot
        )
    }

    /// Preview under the transfer amount: what lands in the destination
    /// after FX. Nil when there's nothing useful to add — no destination
    /// yet, zero amount, or a same-currency transfer where the figure is
    /// identical to what was typed.
    private var transferPreviewText: String? {
        guard let destination = destinationAccount, amount > 0 else { return nil }
        if amountCurrencyCode == destination.currencyCode { return nil }
        if let dest = transferDestAmount {
            return "≈ \(dest.formatted(.currency(code: destination.currencyCode))) יתקבלו בחשבון היעד"
        }
        return "שערי חליפין לא זמינים — לא ניתן להמיר ל-\(destination.currencyCode)."
    }

    private var canConfirm: Bool {
        if kind == .transfer {
            // Need two *distinct* accounts, a positive amount, and a rate
            // that can express it in the destination's currency — without
            // the last, the credit would silently skip.
            guard let source = sourceAccount,
                  let destination = destinationAccount,
                  source.persistentModelID != destination.persistentModelID,
                  amount > 0,
                  transferDestAmount != nil
            else { return false }
            return true
        }
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
        // Editing keeps the same slide gesture but reframes it as saving
        // changes rather than adding a new row.
        if editingTransaction != nil {
            return "החליקו לשמירת השינויים"
        }
        switch kind {
        case .income:   return "החליקו להוספת הכנסה"
        case .expense:  return "החליקו להוספת הוצאה"
        case .transfer: return "החליקו לביצוע ההעברה"
        }
    }

    /// Colour that themes the confirm slider and the post-confirm glow,
    /// keyed to the kind being committed: income green, expense red,
    /// transfer the brand accent.
    private var kindTint: Color {
        switch kind {
        case .income:   return Theme.Colors.income
        case .expense:  return Theme.Colors.expense
        case .transfer: return Theme.Colors.accent
        }
    }

    /// Transition the form sections use as the layout swaps between the
    /// income/expense and transfer modes. Collapses to `.identity` under
    /// Reduce Motion so the swap is an instant cut.
    private var kindTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    }

    /// A soft band of `kindTint` that blooms up from the bottom of the
    /// sheet the instant the user confirms, then the sheet dismisses over
    /// it — a quick, themed "done" flash. Kept in the tree (at zero
    /// opacity) so flipping `hasConfirmed` animates rather than hard-cuts.
    /// Under Reduce Motion it only cross-fades (no upward bloom).
    private var confirmGlow: some View {
        kindTint
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .blur(radius: 70)
            .opacity(hasConfirmed ? (reduceMotion ? 0.22 : 0.32) : 0)
            .scaleEffect(reduceMotion ? 1 : (hasConfirmed ? 1 : 0.7), anchor: .bottom)
            .animation(reduceMotion ? .easeOut(duration: 0.3) : .easeOut(duration: 0.55), value: hasConfirmed)
            .allowsHitTesting(false)
            .ignoresSafeArea()
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
        guard canConfirm else { return }

        let saved: Transaction
        if kind == .transfer {
            guard let source = sourceAccount,
                  let destination = destinationAccount,
                  let destAmount = transferDestAmount
            else { return }
            saved = insertTransfer(source: source, destination: destination, destAmount: destAmount)
        } else {
            guard let account = sourceAccount,
                  let kindModel = kind.transactionKind,
                  let accountAmount = amountInAccountCurrency(amount, account)
            else { return }
            saved = editingTransaction.map { existing in
                applyEdit(to: existing, account: account, kindModel: kindModel, accountAmount: accountAmount)
            } ?? insertNew(account: account, kindModel: kindModel, accountAmount: accountAmount)
        }

        try? modelContext.save()
        onSaved?(saved)

        // Light the themed glow (driven by `hasConfirmed`), then dismiss
        // once it's registered. The short delay also lets the slider's
        // checkmark snap in before the sheet slides away.
        hasConfirmed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            dismiss()
        }
    }

    /// Insert a transfer row and move the money: debit the source by
    /// `amount` (in the source's own currency) and credit the destination
    /// by `destAmount` (already converted into the destination's
    /// currency). Both figures are stored on the row so the later reversal
    /// (delete) needs no FX. `kind` is left at its default and ignored —
    /// the non-nil `destinationAmount` is what marks the row a transfer.
    private func insertTransfer(source: Account, destination: Account, destAmount: Decimal) -> Transaction {
        let now = Date.now
        source.balance -= amount
        destination.balance += destAmount
        source.lastUpdated = now
        destination.lastUpdated = now

        let transfer = Transaction(
            amount: amount,
            date: now,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: details.trimmingCharacters(in: .whitespacesAndNewlines),
            currencyCode: amountCurrencyCode,
            // The source's running balance after the debit — same role as
            // an ordinary row's `balanceAfter`, denominated in the source
            // account's currency (which the list reads back from `account`).
            balanceAfter: source.balance,
            account: source,
            destinationAccount: destination,
            destinationAmount: destAmount
        )
        modelContext.insert(transfer)
        return transfer
    }

    /// Insert a brand-new transaction and roll the account balance.
    private func insertNew(account: Account, kindModel: TransactionKind, accountAmount: Decimal) -> Transaction {
        // Roll the balance with the transaction in the account's own
        // currency: income adds, expense subtracts. `accountAmount` is
        // already converted if the user typed a different currency.
        applyEffect(kindModel, accountAmount, to: account)
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
        return transaction
    }

    /// Update an existing transaction. The net balance change is "new
    /// effect minus old effect": we first reverse the row's *original*
    /// impact on its old account (read off the row before we mutate it),
    /// then apply the freshly-entered impact to the chosen account. When
    /// the account is unchanged this collapses to just the delta; when it
    /// changes, the old account is made whole and the new one absorbs the
    /// full amount. The row's `date` is left untouched so it keeps its
    /// place in the history.
    private func applyEdit(to existing: Transaction, account: Account, kindModel: TransactionKind, accountAmount: Decimal) -> Transaction {
        // Reverse first — `balanceEffect` reads the row's *current* (old)
        // amount/kind/currency and account, so it has to run before the
        // fields below are overwritten.
        if let oldAccount = existing.account,
           let oldEffect = existing.balanceEffect(using: fxSnapshots.first) {
            oldAccount.balance -= oldEffect
            oldAccount.lastUpdated = .now
        }

        applyEffect(kindModel, accountAmount, to: account)
        account.lastUpdated = .now

        existing.amount = amount
        existing.kind = kindModel
        existing.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        existing.note = details.trimmingCharacters(in: .whitespacesAndNewlines)
        existing.currencyCode = amountCurrencyCode
        existing.category = category
        existing.account = account
        existing.balanceAfter = account.balance
        return existing
    }

    /// Apply a signed amount to an account's balance: income adds,
    /// expense subtracts. Shared by the insert and edit paths so the
    /// sign convention lives in one place.
    private func applyEffect(_ kind: TransactionKind, _ accountAmount: Decimal, to account: Account) {
        switch kind {
        case .income:  account.balance += accountAmount
        case .expense: account.balance -= accountAmount
        }
    }
}

// MARK: - Sheet-local kind

/// The three options shown in the segmented picker. Stored separately
/// from `TransactionKind` so the sheet can model "transfer" without
/// polluting the persistence-level enum (which `Category` and `BudgetItem`
/// share, and where a third case would be meaningless — see CLAUDE.md).
/// A confirmed transfer persists as a single `Transaction` flagged by its
/// `destinationAmount` (`Transaction.isTransfer`), not as a new kind.
enum SheetKind: String, CaseIterable, Identifiable {
    case income
    case expense
    case transfer

    var id: String { rawValue }

    /// Bridge *up* from the persistence-level enum, used when seeding the
    /// sheet to edit an existing row. Transfers are delete-only (never
    /// reopened for editing), so `.transfer` is unreachable here.
    init(_ kind: TransactionKind) {
        switch kind {
        case .income:  self = .income
        case .expense: self = .expense
        }
    }

    var hebrewLabel: String {
        switch self {
        case .income:   return "הכנסה"
        case .expense:  return "הוצאה"
        case .transfer: return "העברה בין חשבונות"
        }
    }

    /// Bridge to the persistence-level enum. Nil for transfer — it isn't
    /// an income/expense kind; the confirm path handles it separately and
    /// stores it as a transfer row.
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

// MARK: - Transfer flow arrow

/// The flowing arrow shown between the two transfer chips: three chevrons
/// that "march" toward the destination to suggest money crossing over.
///
/// Pinned to LTR internally so the chevrons always point the same visual
/// direction regardless of the sheet's RTL environment (SF directional
/// symbols otherwise auto-mirror). When `animated` is false (Reduce
/// Motion) it renders a single static, dimmed set. `accessibilityHidden`
/// because it's pure decoration — the two account chips carry the meaning.
private struct TransferFlowArrow: View {
    let animated: Bool

    var body: some View {
        Group {
            if animated {
                // PhaseAnimator with no trigger loops through the phases
                // forever, giving a continuous marching highlight.
                PhaseAnimator([0, 1, 2]) { phase in
                    chevrons(highlight: phase)
                }
            } else {
                chevrons(highlight: nil)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private func chevrons(highlight: Int?) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<3) { index in
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.Colors.accent)
                    // Brighten the marching chevron; the highlight walks
                    // right-to-left (2 → 0) so motion reads source →
                    // destination, matching the RTL chip order.
                    .opacity(opacity(for: index, highlight: highlight))
            }
        }
        .frame(width: 44)
    }

    private func opacity(for index: Int, highlight: Int?) -> Double {
        guard let highlight else { return 0.55 }
        return index == (2 - highlight) ? 1 : 0.3
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
