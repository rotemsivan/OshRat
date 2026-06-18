import SwiftUI

/// Modal form used for both *adding* a new account during onboarding
/// and *editing* one of the drafts already in the list.
///
/// It works on a local copy of the draft (`@State`). The parent only
/// receives the result if the user taps "Save" — tapping "Cancel" or
/// swiping the sheet down throws the edits away.
///
/// The body adapts to the account type:
///   * `.current` / `.digitalWallet` / `.savings` — one balance field, done.
///   * `.investment` — the balance is relabelled as *liquid cash* and a
///     "Holdings" section appears for stocks, ETFs and other assets the
///     user holds in the same account.
struct AccountEditorSheet: View {
    @State private var draft: AccountDraft
    private let isNew: Bool
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

    private let supportedCurrencies: [String] = ["ILS", "USD", "EUR"]

    init(
        draft: AccountDraft,
        isNew: Bool,
        lockCurrency: Bool = false,
        onSave: @escaping (AccountDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._draft = State(initialValue: draft)
        self.isNew = isNew
        self.lockCurrency = lockCurrency
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
                        FavouriteRatToggle(isFavorite: $draft.isFavorite)
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

                balanceSection

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
            Text(draft.type == .investment ? "יתרה במזומן (נזיל)" : "יתרה")
        } footer: {
            Text(balanceFooter)
        }
    }

    private var balanceFooter: LocalizedStringKey {
        switch draft.type {
        case .investment:
            return "בחשבון השקעות, היתרה הזו היא המזומן הנזיל בלבד. השווי של המניות וקרנות הסל ייוסף לפי הרשימה שמתחת."
        default:
            return "היתרה היא הסכום הנוכחי בחשבון. אפשר לעדכן אותה ידנית בכל עת."
        }
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
