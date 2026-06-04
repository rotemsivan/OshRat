import SwiftUI

/// Modal form used for both *adding* a new account during onboarding
/// and *editing* one of the drafts already in the list.
///
/// It works on a local copy of the draft (`@State`). The parent only
/// receives the result if the user taps "Save" — tapping "Cancel" or
/// swiping the sheet down throws the edits away.
struct AccountEditorSheet: View {
    /// The draft being edited. The sheet mutates this local copy and
    /// hands it back through `onSave` on confirmation.
    @State private var draft: AccountDraft

    /// `nil` when we're creating a new account, non-nil when editing —
    /// only used to set the navigation title.
    private let isNew: Bool

    private let onSave: (AccountDraft) -> Void
    private let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Small fixed list of currencies, same as the personal-details step.
    private let supportedCurrencies: [String] = ["ILS", "USD", "EUR", "GBP"]

    init(
        draft: AccountDraft,
        isNew: Bool,
        onSave: @escaping (AccountDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        // Seed the @State with the caller's draft. SwiftUI only honours
        // the initial value here, which is exactly what we want — later
        // edits stay local until "Save".
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

                Section {
                    // TextField with a Decimal binding + .number format
                    // parses what the user typed straight into a Decimal,
                    // which is what the data model stores. No Double, ever.
                    TextField(
                        "יתרה",
                        value: $draft.balance,
                        format: .number
                    )
                    .keyboardType(.decimalPad)

                    Picker("מטבע", selection: $draft.currencyCode) {
                        ForEach(supportedCurrencies, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                } footer: {
                    Text("היתרה היא הסכום הנוכחי בחשבון. אפשר לעדכן אותה ידנית בכל עת.")
                }
            }
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
