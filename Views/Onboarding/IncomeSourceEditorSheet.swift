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
                    TextField("שם מקור ההכנסה", text: $draft.name)
                        .submitLabel(.next)
                        .multilineTextAlignment(.trailing)
                } footer: {
                    Text("למשל: משכורת, עבודה צדדית, השכרת דירה.")
                }

                Section {
                    TextField(
                        "סכום חודשי מתוכנן",
                        value: $draft.plannedAmount,
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
                    Text("הסכום החודשי הצפוי. אם הוא משתנה — רשמו ממוצע משוער ועדכנו בעתיד.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
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
    .environment(\.layoutDirection, .rightToLeft)
}
