import SwiftUI

/// Step 2 of the setup wizard: collect the user's financial accounts.
///
/// We deliberately separate "the account exists with this balance" (here)
/// from "transactions over time" (later). The balance is the source of
/// truth for net worth — we don't auto-derive it from transactions.
struct AccountsStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    @State private var editingDraft: AccountDraft?
    @State private var isEditingNewDraft: Bool = false

    var body: some View {
        List {
            Section {
                if viewModel.accountDrafts.isEmpty {
                    Text("עדיין לא הוספת חשבונות. הוסיפו לפחות חשבון אחד כדי להמשיך.")
                        //.font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    ForEach(viewModel.accountDrafts) { draft in
                        Button {
                            isEditingNewDraft = false
                            editingDraft = draft
                        } label: {
                            AccountDraftRow(draft: draft)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: viewModel.deleteAccounts(at:))
                }
            } header: {
                Text("החשבונות שלי")
            } footer: {
                Text("הוסיפו עו״ש, חיסכון או תיק השקעות. אפשר להוסיף ולמחוק חשבונות גם בהמשך.")
            }

            Section {
                Button {
                    isEditingNewDraft = true
                    editingDraft = AccountDraft(currencyCode: viewModel.preferredCurrencyCode)
                } label: {
                    Label("הוספת חשבון", systemImage: "plus.circle.fill")
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .sheet(item: $editingDraft) { draft in
            AccountEditorSheet(
                draft: draft,
                isNew: isEditingNewDraft,
                onSave: { updated in
                    if isEditingNewDraft {
                        viewModel.addAccount(updated)
                    } else {
                        viewModel.update(updated)
                    }
                },
                onCancel: {}
            )
        }
    }
}

/// One row in the accounts list. Visually matches the dashboard's
/// `AssetsSummaryCard.AccountSummaryRow` — accent-colour SF Symbol on
/// the leading edge, name with an optional favourite star on top, type
/// + holdings count underneath, total on the trailing side. Keeping
/// the two rows lockstep means the user sees the same account "card"
/// shape in onboarding and on the dashboard, so the mental model
/// carries over without re-learning.
private struct AccountDraftRow: View {
    let draft: AccountDraft

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbolName)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(draft.name.isEmpty ? "ללא שם" : draft.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if draft.isFavorite {
                        // Tiny inline star so the favourite is visible
                        // at a glance without opening the editor.
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.yellow)
                            .accessibilityLabel(Text("חשבון מועדף"))
                    }
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
            Text(formattedTotal)
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
        }
        .contentShape(.rect)
    }

    private var subtitle: String {
        if draft.type == .investment, !draft.holdings.isEmpty {
            // Localized so the holdings count pluralizes correctly in Hebrew.
            let holdings = String(localized: "\(draft.holdings.count) נכסים")
            return "\(draft.type.hebrewLabel) • \(holdings)"
        }
        return draft.type.hebrewLabel
    }

    /// For most accounts, just the balance. For investment accounts we
    /// also add the sum of same-currency holdings — mixed-currency
    /// holdings need real FX, which is a later milestone.
    private var formattedTotal: String {
        var total = draft.balance
        if draft.type == .investment {
            for holding in draft.holdings where holding.currencyCode == draft.currencyCode {
                total += holding.marketValue
            }
        }
        return total.formatted(.currency(code: draft.currencyCode))
    }

    private var symbolName: String {
        switch draft.type {
        case .current:       return "banknote"
        case .digitalWallet: return "wallet.bifold"
        case .savings:       return "lock"
        case .investment:    return "chart.line.uptrend.xyaxis"
        }
    }
}

#Preview {
    AccountsStepView(viewModel: {
        let vm = OnboardingViewModel()
        vm.accountDrafts = [
            AccountDraft(name: "עו״ש", type: .current, balance: 4200, currencyCode: "ILS"),
            AccountDraft(name: "חיסכון", type: .savings, balance: 15000, currencyCode: "ILS")
        ]
        return vm
    }())
}
