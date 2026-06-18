import SwiftUI

/// Modal form for adding or editing a single income source during the
/// budget step. Mirrors `AccountEditorSheet`: the parent passes in a
/// draft, we mutate a local copy, and only call back through `onSave`
/// when the user confirms.
struct IncomeSourceEditorSheet: View {
    @State private var draft: IncomeSourceDraft
    private let isNew: Bool
    private let onSave: (IncomeSourceDraft) -> Void
    private let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let supportedCurrencies: [String] = ["ILS", "USD", "EUR", "GBP"]

    init(
        draft: IncomeSourceDraft,
        isNew: Bool,
        onSave: @escaping (IncomeSourceDraft) -> Void,
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
                    HebrewTextField("שם מקור ההכנסה", text: $draft.name, submitLabel: .next)
                } footer: {
                    Text("למשל: משכורת, עבודה צדדית, השכרת דירה.")
                }

                Section {
                    // Same big amount + inline currency field used across
                    // the app's money inputs. Row background cleared so only
                    // the field's own card shows.
                    BigAmountField(
                        value: $draft.plannedAmount,
                        currencyCode: $draft.currencyCode,
                        supportedCurrencies: supportedCurrencies
                    )
                    .listRowBackground(Color.clear)
                } header: {
                    Text("סכום מתוכנן")
                } footer: {
                    Text("הסכום הצפוי. אם הוא משתנה — רשמו ממוצע משוער ועדכנו בעתיד.")
                }

                // Income doesn't use the averaged sub-monthly cadences (a
                // salary doesn't arrive "every few days"), so we hide them and
                // offer only monthly / every-N-months / yearly / one-off.
                BudgetScheduleSection(
                    schedule: $draft.schedule,
                    allowsSubMonthlyCadence: false,
                    currencyCode: draft.currencyCode,
                    plannedAmount: draft.plannedAmount
                )
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .font(Theme.Typography.body)
            .navigationTitle(isNew ? Text("מקור הכנסה חדש") : Text("עריכת מקור הכנסה"))
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
}

#Preview {
    IncomeSourceEditorSheet(
        draft: IncomeSourceDraft(),
        isNew: true,
        onSave: { _ in },
        onCancel: {}
    )
}
