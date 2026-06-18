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
                    allowsSubMonthlyCadence: true,
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
        }
    }

    private var amountSection: some View {
        Section {
            // Same big amount + inline currency field used across the app's
            // money inputs. Row background cleared so only the field's own
            // card shows.
            BigAmountField(
                value: $draft.plannedAmount,
                currencyCode: $draft.currencyCode,
                supportedCurrencies: supportedCurrencies
            )
            .listRowBackground(Color.clear)
        } header: {
            Text("סכום מתוכנן")
        } footer: {
            Text(amountFooterText)
        }
    }

    /// The amount's meaning depends on the cadence the user picked, so the
    /// footer adapts: per-occurrence for averaged cadences, the single sum
    /// for landing / one-off lines, the monthly figure for plain monthly.
    private var amountFooterText: String {
        let schedule = draft.schedule
        if schedule.isOneTime {
            return "הסכום של ההוצאה החד־פעמית."
        }
        switch schedule.unit {
        case .day, .week:
            return "הסכום עבור כל פעם — לדוגמה כמה עולה ביקור אחד אצל הספר."
        case .month:
            return schedule.count > 1
                ? "הסכום המלא שייכנס בכל פעם שזה חוזר."
                : "הסכום החודשי המתוכנן."
        case .year:
            return "הסכום שייכנס פעם בשנה, בחודש שנבחר."
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
