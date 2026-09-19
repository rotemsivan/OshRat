import SwiftUI
import SwiftData

/// Modal form used for both *adding* a new account during onboarding
/// and *editing* one of the drafts already in the list.
///
/// It works on a local copy of the draft (`@State`). The parent only
/// receives the result if the user taps "Save" — tapping "Cancel" or
/// swiping the sheet down throws the edits away.
///
/// The body adapts to the account type:
///   * `.current` / `.digitalWallet` — one balance field, done.
///   * `.savings` — the balance is relabelled as the *deposit amount* and a
///     "deposit terms" section appears: rate, start and maturity dates, where
///     the money goes at maturity, and whether it should go there on its own.
///     Every one of those is optional, so a plain open-ended savings pot is
///     still just a balance.
///   * `.investment` — currently **blocked** (see `investmentNote`); existing
///     investment accounts still open and edit normally, showing the liquid
///     cash field and their "Holdings" list.
struct AccountEditorSheet: View {
    @State private var draft: AccountDraft
    private let isNew: Bool
    /// Accounts this deposit could pay out into — live עו״ש accounts, minus
    /// the deposit itself. The caller does the filtering: `HomeView` offers the
    /// saved accounts, `AccountsStepView` the other drafts in the wizard (see
    /// `OnboardingViewModel.payoutCandidates`). Taken as value references
    /// rather than models so both callers feed the same picker.
    private let payoutCandidates: [PayoutCandidate]
    /// The type the account already had when the sheet opened. Investments
    /// are blocked, but an account that *is* one must still be editable — so
    /// `.investment` stays selectable only when it's where we started.
    private let originalType: AccountType
    /// When true, the currency picker is replaced with a read-only
    /// label. Used by the dashboard's edit-account flow where the
    /// account is already persisted: changing its currency would
    /// invalidate the stored balance and the transaction history that
    /// hangs off it. During onboarding (both add and re-edit of a
    /// freshly added draft) nothing is committed yet, so the picker
    /// stays editable and the caller passes `false`.
    private let lockCurrency: Bool
    private let onSave: (AccountDraft) -> Void
    private let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Width of the "ריבית שנתית" field. A rate is at most three digits
    /// (plus a decimal), so the field is sized to that instead of stretching
    /// across the row and reading like a full-width amount field.
    /// `@ScaledMetric` so it grows with Dynamic Type rather than clipping the
    /// digits at the larger text sizes.
    @ScaledMetric(relativeTo: .body) private var rateFieldWidth: CGFloat = 56

    private let supportedCurrencies: [String] = ["ILS", "USD", "EUR"]

    init(
        draft: AccountDraft,
        isNew: Bool,
        lockCurrency: Bool = false,
        payoutCandidates: [PayoutCandidate] = [],
        onSave: @escaping (AccountDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._draft = State(initialValue: draft)
        self.isNew = isNew
        self.lockCurrency = lockCurrency
        self.payoutCandidates = payoutCandidates
        self.originalType = draft.type
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: Theme.Spacing.sm) {
                        // Favourite toggle in line with — but visually
                        // separate from — the name field. RTL reads as
                        // rat → small gap → boxed field. Selecting it fires
                        // the window-wide glow below.
                        //
                        // Deposits can't be the go-to account (see
                        // `AccountType.allowsFavorite`), so the rat simply
                        // isn't offered for them — the field then takes the
                        // full row width rather than leaving a dead gap.
                        if draft.type.allowsFavorite {
                            FavouriteRatToggle(isFavorite: $draft.isFavorite)
                        }
                        HebrewTextField("שם החשבון", text: $draft.name, submitLabel: .next)
                            .padding(Theme.Spacing.md)
                            .background(Theme.Colors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                                    .stroke(Theme.Colors.separator, lineWidth: 1)
                            )
                    }
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("למשל: עו״ש בנק הפועלים, חיסכון, תיק השקעות.")
                }

                // Segmented "slide" picker across the four account types.
                // The row background is cleared so the control floats on the
                // sheet background instead of a white capsule, and the
                // top/bottom row insets are trimmed so it isn't boxed in
                // vertical whitespace. The "סוג" title stays for VoiceOver
                // though the segmented style hides it.
                Picker("סוג", selection: $draft.type) {
                    ForEach(AccountType.allCases) { type in
                        Text(type.hebrewLabel).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.md, bottom: 0, trailing: Theme.Spacing.md))
                // השקעות isn't built yet. The segment stays visible — it's
                // coming, and hiding it would make the feature a surprise
                // later — but picking it bounces straight back, with the note
                // below saying why. A segmented `Picker` can't disable one of
                // its segments, so bouncing the selection is the honest way to
                // express "visible but not yet available".
                .onChange(of: draft.type) { previous, selected in
                    // Switching *to* a deposit drops the star: the toggle
                    // disappears with the type change, so without this the
                    // flag would stay set on a draft the user can no longer
                    // see or clear, and save it onto the account.
                    if !selected.allowsFavorite { draft.isFavorite = false }
                    guard selected == .investment, originalType != .investment else { return }
                    draft.type = previous == .investment ? .current : previous
                }

                investmentNote

                balanceSection

                if draft.type == .savings {
                    depositSection
                }

                if draft.type == .investment {
                    holdingsSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            // Force Heebo on the whole Form. SwiftUI's environment `.font`
            // from the app root doesn't always reach `TextField`, `Picker`
            // labels, and section headers inside `Form` — particularly in
            // sheets — so we re-apply it here.
            .font(Theme.Typography.body)
            .navigationTitle(isNew ? Text("חשבון חדש") : Text("עריכת חשבון"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .tint(Theme.Colors.accent)
        // Siri-style glow that sweeps the whole window when the account is
        // marked favourite. Lives at the sheet root (not on the rat) so it
        // can span the full window; fires off `draft.isFavorite` flipping on.
        .overlay {
            FavouriteWindowGlow(isActive: draft.isFavorite)
        }
    }

    // MARK: - Sections

    private var balanceSection: some View {
        Section {
            // Mirrors the "סכום" field in NewTransactionSheet: one big
            // balance number with the currency on the same row, reading as
            // a single editable unit. The row background is cleared so only
            // the field's own card shows (no double surface).
            //
            // `isCurrencyLocked` is on for the dashboard edit flow — a
            // persisted account's balance, history and running-balance
            // snapshots are all in its currency, with no sensible
            // conversion, so the code is read-only there. Onboarding drafts
            // aren't committed yet, so they stay editable.
            BigAmountField(
                value: $draft.balance,
                currencyCode: $draft.currencyCode,
                supportedCurrencies: supportedCurrencies,
                isCurrencyLocked: lockCurrency
            )
            .listRowBackground(Color.clear)
        } header: {
            Text(balanceHeader)
        } footer: {
            Text(balanceFooter)
        }
    }

    private var balanceHeader: LocalizedStringKey {
        switch draft.type {
        case .investment: return "יתרה במזומן (נזיל)"
        case .savings:
            // On a replenishable deposit the field means two different things
            // either side of the first save: the opening deposit while it's
            // being created, the running total once transfers have added to it.
            guard draft.isReplenishable else { return "סכום ההפקדה" }
            return isNew ? "סכום ההפקדה הראשונה" : "סך הכסף בפיקדון"
        default:          return "יתרה"
        }
    }

    private var balanceFooter: LocalizedStringKey {
        switch draft.type {
        case .investment:
            return "בחשבון השקעות, היתרה הזו היא המזומן הנזיל בלבד. השווי של המניות וקרנות הסל ייוסף לפי הרשימה שמתחת."
        case .savings:
            if draft.isReplenishable {
                return "הסכום שנמצא בפיקדון עכשיו. כל העברה נוספת אליו תיפתח כהפקדה נפרדת עם התקופה והריבית שלה."
            }
            return "הסכום שהופקד. הריבית מחושבת עליו ותיווסף במועד הפדיון."
        default:
            return "היתרה היא הסכום הנוכחי בחשבון. אפשר לעדכן אותה ידנית בכל עת."
        }
    }

    // MARK: - Investments (blocked)

    /// Explains why השקעות can't be picked. Shown under the type picker
    /// whenever investments aren't already this account's type, so the user
    /// reads it *before* tapping the segment and having it bounce back.
    @ViewBuilder
    private var investmentNote: some View {
        if originalType != .investment {
            Label("חשבונות השקעות בפיתוח — אפשר לרשום קניות ומכירות ני״ע כתנועות רגילות בינתיים.", systemImage: "hammer")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(
                    top: Theme.Spacing.xs,
                    leading: Theme.Spacing.md,
                    bottom: 0,
                    trailing: Theme.Spacing.md
                ))
        }
    }

    // MARK: - Deposit terms

    /// Savings-only: the terms that turn a pot of money into a deposit.
    /// Everything here is optional — leave the rate at zero and the maturity
    /// toggle off and you have a plain savings account that behaves exactly
    /// as it did before deposits existed.
    private var depositSection: some View {
        Section {
            // The one decision that changes what everything below *means*, so
            // it sits first: a one-time deposit's terms are its own, while a
            // replenishable deposit's are the defaults each future deposit
            // inherits.
            Toggle("אפשר הפקדות נוספות", isOn: $draft.isReplenishable.animation(.easeInOut(duration: 0.2)))

            LabeledContent(rateLabel) {
                HStack(spacing: Theme.Spacing.xs) {
                    DecimalField(placeholder: "0", value: $draft.interestRatePercent)
                        .frame(width: rateFieldWidth)
                    Text(verbatim: "%")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            DatePicker(
                startDateLabel,
                selection: $draft.depositStartDate,
                displayedComponents: .date
            )

            Toggle("תאריך פדיון", isOn: $draft.hasMaturityDate.animation(.easeInOut(duration: 0.2)))

            if draft.hasMaturityDate {
                DatePicker(
                    maturityLabel,
                    selection: $draft.maturityDate,
                    in: draft.depositStartDate...,
                    displayedComponents: .date
                )

                payoutTargetPicker

                Toggle("העברה אוטומטית במועד הפדיון", isOn: $draft.autoPayoutOnMaturity)
            }

            projectedValueRow
        } header: {
            Text("תנאי הפיקדון")
        } footer: {
            Text(depositFooter)
        }
    }

    /// On a replenishable deposit every term on this screen is a *default* for
    /// the deposits still to come, not a fact about money already in — the
    /// labels say so rather than leaving the user to infer it.
    private var rateLabel: LocalizedStringKey {
        draft.isReplenishable ? "ריבית שנתית (ברירת מחדל)" : "ריבית שנתית"
    }

    private var startDateLabel: LocalizedStringKey {
        draft.isReplenishable ? "תאריך ההפקדה הראשונה" : "תאריך הפקדה"
    }

    private var maturityLabel: LocalizedStringKey {
        draft.isReplenishable ? "מועד הפדיון של ההפקדה הראשונה" : "מועד הפדיון"
    }

    /// Where the money lands at maturity — an עו״ש account. Falls back to a
    /// read-only label only when there is genuinely nothing to choose between
    /// (the user has no current account at all); the payout prompt asks again
    /// at maturity in that case.
    ///
    /// During onboarding the candidates are the *other drafts* in the wizard,
    /// which is why this takes `PayoutCandidate` values instead of models —
    /// before, onboarding passed an empty list and the user was stuck with
    /// "ייבחר בפדיון" no matter how many accounts they had just added.
    @ViewBuilder
    private var payoutTargetPicker: some View {
        if payoutCandidates.isEmpty {
            LabeledContent("חשבון היעד") {
                Text("ייבחר בפדיון")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        } else {
            Picker("חשבון היעד", selection: $draft.payoutTarget) {
                Text("ייבחר בפדיון").tag(PayoutTargetRef?.none)
                ForEach(payoutCandidates) { candidate in
                    Text(candidate.displayName)
                        .tag(PayoutTargetRef?.some(candidate.id))
                }
            }
        }
    }

    /// What the deposit is projected to be worth when it matures — the same
    /// figure the payout prompt will pre-fill, shown here so the terms can be
    /// sanity-checked while they're being typed.
    ///
    /// Skipped for a replenishable deposit that already exists: this screen
    /// only knows the account's own terms, so it would project the *whole*
    /// balance on them and quietly ignore the sub-deposits' own rates and
    /// dates. The deposit's own card (`DepositInfoSheet`) does that sum
    /// properly, and it's one tap away.
    @ViewBuilder
    private var projectedValueRow: some View {
        if isNew || !draft.isReplenishable,
           let terms = draft.previewTerms, terms.projectedInterest != 0 {
            LabeledContent("צפוי בפדיון") {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(terms.projectedValue.formatted(.currency(code: draft.currencyCode)))
                        .font(Theme.Typography.amount)
                        .monospacedDigit()
                    Text("ריבית \(terms.projectedInterest.formatted(.currency(code: draft.currencyCode)))")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.income)
                        .monospacedDigit()
                }
            }
        }
    }

    private var depositFooter: LocalizedStringKey {
        // The replenishable case leads with the rule that surprises people:
        // each transfer in becomes a deposit of its own, and the account only
        // comes due when the *last* of them does.
        if draft.isReplenishable {
            return draft.hasMaturityDate
                ? "כל העברה לפיקדון הזה תיפתח כהפקדה נפרדת, עם אותה ריבית ואותו אורך תקופה, שנספרים מיום ההעברה. הפיקדון כולו ייפדה במועד המאוחר מבין ההפקדות."
                : "כל העברה לפיקדון הזה תיפתח כהפקדה נפרדת. בלי תאריך פדיון זהו חיסכון פתוח — לא נזכיר כלום ולא תופיע העברה."
        }
        if draft.autoPayoutOnMaturity && draft.payoutTarget != nil {
            return "במועד הפדיון הכסף יועבר אוטומטית לחשבון היעד, והריבית תירשם כהכנסה."
        }
        if draft.hasMaturityDate {
            return "במועד הפדיון נזכיר לך להעביר את הכסף, ואפשר יהיה לבחור חשבון יעד אחר."
        }
        return "בלי תאריך פדיון זהו חיסכון פתוח — לא נזכיר כלום ולא תופיע העברה."
    }

    /// Investment-only: a list of holdings (stocks, ETFs, anything) with
    /// add / edit / delete. Each row pushes the holding editor onto the
    /// sheet's `NavigationStack`.
    private var holdingsSection: some View {
        Section {
            ForEach(draft.holdings) { holding in
                NavigationLink {
                    HoldingEditorView(
                        draft: holding,
                        isNew: false,
                        onSave: { updated in
                            if let index = draft.holdings.firstIndex(where: { $0.id == updated.id }) {
                                draft.holdings[index] = updated
                            }
                        }
                    )
                } label: {
                    HoldingDraftRow(holding: holding)
                }
            }
            .onDelete { offsets in
                for index in offsets.sorted(by: >) {
                    draft.holdings.remove(at: index)
                }
            }

            NavigationLink {
                HoldingEditorView(
                    draft: HoldingDraft(currencyCode: draft.currencyCode),
                    isNew: true,
                    onSave: { newHolding in
                        draft.holdings.append(newHolding)
                    }
                )
            } label: {
                Label("הוספת נכס", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.Colors.accent)
            }
        } header: {
            Text("נכסים בחשבון")
        } footer: {
            Text("מניות, תעודות סל (ETF), קרנות, אג״ח או כל נכס אחר. נכסים בלבד — המזומן הנזיל מנוהל בשדה היתרה למעלה.")
        }
    }
}

// MARK: - Favourite toggle

/// Small rat mascot, in line with the name field, that marks this account
/// as the favourite (the default account pre-selected in "תנועה חדשה").
/// Desaturated + dimmed when off, full colour with a gentle pop when on.
/// The celebratory flourish on selection is the window-wide glow at the
/// sheet root (`FavouriteWindowGlow`), not anything on the icon itself.
///
/// Accessibility: the icon carries no inherent "favourite" meaning, so we
/// give it an explicit label, an on/off value, the selected trait, and a
/// hint. State is conveyed by saturation + opacity (never colour alone),
/// and the pop collapses to a plain crossfade under Reduce Motion.
private struct FavouriteRatToggle: View {
    @Binding var isFavorite: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size: CGFloat = 40

    var body: some View {
        Button {
            isFavorite.toggle()
        } label: {
            Image("rat-mascot-thumbsup")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .saturation(isFavorite ? 1 : 0)
                .opacity(isFavorite ? 1 : 0.4)
                .scaleEffect(reduceMotion ? 1 : (isFavorite ? 1 : 0.9))
                // Pad to a ≥44pt tap target without enlarging the glyph.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.6),
            value: isFavorite
        )
        .accessibilityLabel(Text("חשבון מועדף"))
        .accessibilityValue(Text(isFavorite ? "פעיל" : "כבוי"))
        .accessibilityHint(Text("סימון החשבון כברירת מחדל לתנועה חדשה"))
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
    }
}

// MARK: - Window glow

/// A gentle golden glow that washes diagonally across the edge of the
/// whole sheet when an account is marked favourite. Fires once each time
/// `isActive` flips to true: a soft, blurred golden border (lit
/// top-leading → bottom-trailing for a diagonal feel) fades in, holds,
/// then fades out. Edge-only and non-interactive, so it never blocks the
/// form. It deliberately does **not** fire on appear, so opening an
/// already-favourite account stays calm — only an actual selection glows.
private struct FavouriteWindowGlow: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var opacity: Double = 0

    /// Diagonal (top-leading → bottom-trailing) gradient of warm golds —
    /// light at one corner, deeper at the other — for a soft golden sheen.
    private var goldGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.99, green: 0.88, blue: 0.58),
                Color(red: 0.85, green: 0.65, blue: 0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 40, style: .continuous)
            .strokeBorder(goldGradient, lineWidth: 14)
            .blur(radius: 18)
            .opacity(opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: isActive) { _, active in
                if active { fire() }
            }
    }

    /// Soft fade in → brief hold → fade out. Already gentle (pure opacity),
    /// so Reduce Motion only shortens the hold rather than changing kind.
    private func fire() {
        withAnimation(.easeOut(duration: 0.45)) { opacity = 0.6 }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.5 : 0.75)) {
            withAnimation(.easeIn(duration: 0.7)) { opacity = 0 }
        }
    }
}

// MARK: - Row

private struct HoldingDraftRow: View {
    let holding: HoldingDraft

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(displayTitle)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer()
            Text(holding.marketValue.formatted(.currency(code: holding.currencyCode)))
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }

    private var displayTitle: String {
        let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = holding.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !symbol.isEmpty { return symbol }
        if !name.isEmpty { return name }
        return "ללא שם"
    }

    private var subtitle: String {
        let symbol = holding.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = holding.name.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if !symbol.isEmpty, !name.isEmpty {
            parts.append(name)
        }
        if holding.quantity > 0 {
            parts.append("\(holding.quantity.formatted(.number)) יח׳")
        }
        return parts.joined(separator: " • ")
    }
}

#Preview("New") {
    AccountEditorSheet(
        draft: AccountDraft(),
        isNew: true,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Investment") {
    AccountEditorSheet(
        draft: AccountDraft(
            name: "תיק השקעות",
            type: .investment,
            balance: 1200,
            currencyCode: "ILS",
            holdings: [
                HoldingDraft(symbol: "TEVA", name: "טבע", quantity: 50, marketValue: 1750),
                HoldingDraft(symbol: "VOO", name: "Vanguard S&P 500", quantity: 5, marketValue: 9500, currencyCode: "USD")
            ]
        ),
        isNew: false,
        onSave: { _ in },
        onCancel: {}
    )
}
