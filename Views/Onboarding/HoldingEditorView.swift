import SwiftUI

/// Push-style editor for a single holding (stock, ETF, etc.) inside an
/// investment account. Used during onboarding from inside the
/// `AccountEditorSheet`'s navigation stack.
///
/// Unlike the account editor (which is a *sheet* with explicit
/// Cancel/Save), this is a *pushed* view — the system back button is the
/// implicit "cancel" and the toolbar "Save" is the explicit commit.
/// That mirrors how iOS Settings handles drilled-in detail editing.
struct HoldingEditorView: View {
    /// Local copy so edits don't leak into the parent until "Save".
    @State private var draft: HoldingDraft
    private let isNew: Bool
    private let onSave: (HoldingDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Same shortlist as elsewhere in onboarding. Long currency lists are
    /// overwhelming during first-time setup.
    private let supportedCurrencies: [String] = ["ILS", "USD", "EUR", "GBP"]

    init(
        draft: HoldingDraft,
        isNew: Bool,
        onSave: @escaping (HoldingDraft) -> Void
    ) {
        self._draft = State(initialValue: draft)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section {
                TextField("סימול", text: $draft.symbol)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .submitLabel(.next)

                TextField("שם הנכס", text: $draft.name)
                    .submitLabel(.next)
            } header: {
                Text("פרטי הנכס")
            } footer: {
                Text("למשל: TEVA — טבע, או VOO — Vanguard S&P 500. אפשר גם נכסים שאינם מניות, כגון אג״ח או קרנות.")
            }

            Section {
                TextField(
                    "כמות יחידות",
                    value: Binding<Decimal?>(
                        get: { draft.quantity == 0 ? nil : draft.quantity },
                        set: { draft.quantity = $0 ?? 0 }
                    ),
                    format: .number
                )
                .keyboardType(.decimalPad)

                TextField(
                    "שווי שוק נוכחי",
                    value: Binding<Decimal?>(
                        get: { draft.marketValue == 0 ? nil : draft.marketValue },
                        set: { draft.marketValue = $0 ?? 0 }
                    ),
                    format: .number
                )
                .keyboardType(.decimalPad)

                Picker("מטבע", selection: $draft.currencyCode) {
                    ForEach(supportedCurrencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
            } header: {
                Text("שווי והחזקה")
            } footer: {
                Text("שווי השוק הוא הסכום הכולל הנוכחי של ההחזקה. אפשר לעדכן ידנית בכל עת. אם עדיין אין לכם כמות מדויקת — אפשר להשאיר 0 ולעדכן בהמשך.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .font(Theme.Typography.body)
        .navigationTitle(isNew ? Text("נכס חדש") : Text("עריכת נכס"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("שמירה") {
                    onSave(draft)
                    dismiss()
                }
                .disabled(!isSavable)
            }
        }
        .tint(Theme.Colors.accent)
    }

    /// At least a symbol *or* a name is required — a holding with neither
    /// would be impossible to identify later.
    private var isSavable: Bool {
        let trimmedSymbol = draft.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !(trimmedSymbol.isEmpty && trimmedName.isEmpty)
    }
}

#Preview {
    NavigationStack {
        HoldingEditorView(
            draft: HoldingDraft(symbol: "TEVA", name: "טבע", quantity: 50, marketValue: 1750, currencyCode: "ILS"),
            isNew: false,
            onSave: { _ in }
        )
    }
}
