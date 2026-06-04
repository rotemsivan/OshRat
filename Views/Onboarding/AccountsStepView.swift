import SwiftUI

/// Step 2 of the setup wizard: collect the user's financial accounts.
///
/// We deliberately separate "the account exists with this balance" (here)
/// from "transactions over time" (later). The balance is the source of
/// truth for net worth — we don't auto-derive it from transactions.
struct AccountsStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    /// Which draft (if any) is currently being edited in the sheet.
    /// `nil` when no sheet is showing.
    @State private var editingDraft: AccountDraft?

    /// True when the editor sheet is presenting a *new* draft, false when
    /// editing an existing row. Used only to title the sheet.
    @State private var isEditingNewDraft: Bool = false

    var body: some View {
        List {
            Section {
                if viewModel.accountDrafts.isEmpty {
                    // An empty list is a perfectly valid in-progress state;
                    // a row that says "tap + to add" is more inviting than
                    // a totally blank screen.
                    Text("עדיין לא הוספת חשבונות. הוסיפו לפחות חשבון אחד כדי להמשיך.")
                        .foregroundStyle(.secondary)
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
                }
            }
        }
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

/// One row in the accounts list — name on top, type + formatted balance
/// underneath. Kept as a small private view so the parent stays tidy.
private struct AccountDraftRow: View {
    let draft: AccountDraft

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.name.isEmpty ? "ללא שם" : draft.name)
                    .font(.headline)
                Text(draft.type.hebrewLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formattedBalance)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// Formatted using the *account's own* currency code, since the app
    /// is multi-currency. Falls back to a plain decimal if the locale
    /// can't produce a currency string for the code.
    private var formattedBalance: String {
        draft.balance.formatted(.currency(code: draft.currencyCode))
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
    .environment(\.layoutDirection, .rightToLeft)
}
