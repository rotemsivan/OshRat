import SwiftUI
import SwiftData

/// Modal form for adding or editing a single planned expense during the
/// budget step.
///
/// The user picks a category (which carries its own need/want nature),
/// types an optional note (e.g. "ספר" inside "טיפוח"), enters an amount,
/// and chooses how often this expense happens. Non-monthly cadences are
/// stored as "every X weeks" — the dashboard converts to a monthly
/// equivalent so totals roll up cleanly.
struct PlannedExpenseEditorSheet: View {
    /// Available expense categories, passed in from the parent rather
    /// than queried here. Avoids running a second `@Query` inside a
    /// presented sheet, and lets the parent decide the sort order.
    let categories: [Category]

    @State private var draft: PlannedExpenseDraft
    private let isNew: Bool
    private let onSave: (PlannedExpenseDraft) -> Void
    private let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let supportedCurrencies: [String] = ["ILS", "USD", "EUR"]

    init(
        categories: [Category],
        draft: PlannedExpenseDraft,
        isNew: Bool,
        onSave: @escaping (PlannedExpenseDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.categories = categories
        self._draft = State(initialValue: draft)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                categorySection
                noteSection
                amountSection
                frequencySection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .font(Theme.Typography.body)
            .navigationTitle(isNew ? Text("הוצאה חדשה") : Text("עריכת הוצאה"))
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
                    .disabled(draft.category == nil)
                }
            }
        }
        .tint(Theme.Colors.accent)
    }

    // MARK: - Sections

    /// Category picker grouped by nature, so צרכים and רצונות are clearly
    /// separated. Income categories are filtered out — this is for
    /// planned expenses only.
    private var categorySection: some View {
        Section {
            Picker("קטגוריה", selection: $draft.category) {
                Text("בחרו קטגוריה").tag(Optional<Category>.none)

                let needs = expenseCategories.filter { $0.nature == .need }
                if !needs.isEmpty {
                    Section("צרכים") {
                        ForEach(needs) { category in
                            Text(category.name).tag(Optional(category))
                        }
                    }
                }

                let wants = expenseCategories.filter { $0.nature == .want }
                if !wants.isEmpty {
                    Section("רצונות") {
                        ForEach(wants) { category in
                            Text(category.name).tag(Optional(category))
                        }
                    }
                }

                let other = expenseCategories.filter { $0.nature == .neutral }
                if !other.isEmpty {
                    Section("אחר") {
                        ForEach(other) { category in
                            Text(category.name).tag(Optional(category))
                        }
                    }
                }
            }
        } header: {
            Text("קטגוריה")
        } footer: {
            Text("הקטגוריה קובעת אם ההוצאה משויכת לצרכים (חובה) או לרצונות (בחירה).")
        }
    }

    private var noteSection: some View {
        Section {
            TextField("הערה (לא חובה)", text: $draft.note)
                .submitLabel(.next)
        } footer: {
            Text("מקום לפירוט נקודתי, למשל ‘ספר’ או ‘חדר כושר’ בתוך הקטגוריה.")
        }
    }

    private var amountSection: some View {
        Section {
            DecimalField(
                placeholder: "סכום",
                value: $draft.plannedAmount
            )

            Picker("מטבע", selection: $draft.currencyCode) {
                ForEach(supportedCurrencies, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
        } header: {
            Text("סכום מתוכנן")
        } footer: {
            Text(draft.frequencyKind == .monthly
                 ? "הסכום החודשי המתוכנן."
                 : "הסכום עבור כל פעם — לדוגמה כמה עולה ביקור אחד אצל הספר.")
        }
    }

    private var frequencySection: some View {
        Section {
            Picker("תדירות", selection: $draft.frequencyKind) {
                ForEach(BudgetFrequencyKind.allCases) { kind in
                    Text(kind.hebrewLabel).tag(kind)
                }
            }

            if draft.frequencyKind == .everyXWeeks {
                Stepper(value: $draft.frequencyWeeks, in: 1...52) {
                    HStack {
                        Text("כל")
                        Text("\(draft.frequencyWeeks)")
                            .font(.body.monospacedDigit())
                        Text("שבועות")
                    }
                }
                .contentTransition(.numericText(value: Double(draft.frequencyWeeks)))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: draft.frequencyWeeks) // Triggers the motion
            }

            if draft.frequencyKind == .everyXWeeks {
                LabeledContent("שווי חודשי משוער") {
                    Text(monthlyEquivalentPreview.formatted(.currency(code: draft.currencyCode)))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("דוגמה: ‘ספר כל 3 שבועות’ — נחושב ממוצע חודשי שיופיע בדשבורד.")
        }
    }

    // MARK: - Helpers

    /// Expense-only subset of the categories the parent passed in.
    private var expenseCategories: [Category] {
        categories.filter { $0.kind == .expense }
    }

    /// Live preview of what this expense rolls up to per month — uses
    /// the same formula `BudgetItem.monthlyEquivalent` does, so the
    /// editor's preview never disagrees with the dashboard.
    private var monthlyEquivalentPreview: Decimal {
        switch draft.frequencyKind {
        case .monthly:
            return draft.plannedAmount
        case .everyXWeeks:
            let weeks = max(draft.frequencyWeeks, 1)
            return draft.plannedAmount * (Decimal(30) / Decimal(weeks * 7))
        }
    }
}

#Preview {
    PlannedExpenseEditorSheet(
        categories: [],
        draft: PlannedExpenseDraft(),
        isNew: true,
        onSave: { _ in },
        onCancel: {}
    )
}
