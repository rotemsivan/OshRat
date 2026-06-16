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
                BudgetScheduleSection(
                    schedule: $draft.schedule,
                    frequencyKind: $draft.frequencyKind,
                    frequencyWeeks: $draft.frequencyWeeks,
                    allowsWeeklyCadence: true,
                    currencyCode: draft.currencyCode,
                    plannedAmount: draft.plannedAmount
                )
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
            HebrewTextField("הערה (לא חובה)", text: $draft.note, submitLabel: .next)
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
            Text(amountFooterText)
        }
    }

    /// The amount's meaning depends on the schedule the user picked, so the
    /// footer adapts: per-occurrence for weekly cadences, the single sum for
    /// yearly/one-off lines, the monthly figure otherwise.
    private var amountFooterText: String {
        switch draft.schedule.kind {
        case .oneTime:
            return "הסכום של ההוצאה החד־פעמית."
        case .recurringYearly:
            return "הסכום שייכנס פעם בשנה, בחודש שנבחר."
        case .recurringMonthly:
            return draft.frequencyKind == .everyXWeeks
                ? "הסכום עבור כל פעם — לדוגמה כמה עולה ביקור אחד אצל הספר."
                : "הסכום החודשי המתוכנן."
        }
    }

    // MARK: - Helpers

    /// Expense-only subset of the categories the parent passed in.
    /// Collapsed by `(name, kind, nature)` so the picker never shows
    /// the same category twice even if the store still has duplicates.
    private var expenseCategories: [Category] {
        categories.filter { $0.kind == .expense }.semanticallyUnique
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
