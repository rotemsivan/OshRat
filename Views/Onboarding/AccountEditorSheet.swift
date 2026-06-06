import SwiftUI

/// Modal form used for both *adding* a new account during onboarding
/// and *editing* one of the drafts already in the list.
///
/// It works on a local copy of the draft (`@State`). The parent only
/// receives the result if the user taps "Save" — tapping "Cancel" or
/// swiping the sheet down throws the edits away.
///
/// The body adapts to the account type:
///   * `.current` / `.savings` / `.other` — one balance field, done.
///   * `.investment` — the balance is relabelled as *liquid cash* and a
///     "Holdings" section appears for stocks, ETFs and other assets the
///     user holds in the same account.
struct AccountEditorSheet: View {
    @State private var draft: AccountDraft
    private let isNew: Bool
    private let onSave: (AccountDraft) -> Void
    private let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let supportedCurrencies: [String] = ["ILS", "USD", "EUR", "GBP"]

    init(
        draft: AccountDraft,
        isNew: Bool,
        onSave: @escaping (AccountDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._draft = State(initialValue: draft)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("שם החשבון", text: $draft.name)
                        .submitLabel(.next)
                        .multilineTextAlignment(.trailing)
                } footer: {
                    Text("למשל: עו״ש בנק הפועלים, חיסכון, תיק השקעות.")
                }

                Section {
                    Picker("סוג", selection: $draft.type) {
                        ForEach(AccountType.allCases) { type in
                            Text(type.hebrewLabel).tag(type)
                        }
                    }
                }

                balanceSection

                if draft.type == .investment {
                    holdingsSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
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
    }

    // MARK: - Sections

    private var balanceSection: some View {
        Section {
            TextField(
                draft.type == .investment ? "יתרה במזומן (נזיל)" : "יתרה",
                value: $draft.balance,
                format: .number
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)

            Picker("מטבע", selection: $draft.currencyCode) {
                ForEach(supportedCurrencies, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
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
    .environment(\.layoutDirection, .rightToLeft)
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
    .environment(\.layoutDirection, .rightToLeft)
}
