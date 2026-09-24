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
    /// Available categories, passed in from the parent rather than queried
    /// here, which avoids a second `@Query` inside a presented sheet.
    /// `CategoryMenuContent` keeps only the expense ones and orders them.
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

    /// Category picker — the app's one category control: a `Menu` built
    /// from `CategoryMenuContent` (grouped צרכים / רצונות / אחר, alphabetical,
    /// each with its glyph), opened from a bordered `PickerRowLabel`. The
    /// transaction sheet and the transactions filter use the very same pair,
    /// so choosing a category looks and orders the same everywhere.
    ///
    /// The row background is cleared so only the field's own card shows,
    /// matching `BigAmountField` below it.
    private var categorySection: some View {
        Section {
            Menu {
                Button {
                    draft.category = nil
                } label: {
                    Label("בחרו קטגוריה", systemImage: "circle.dashed")
                }

                CategoryMenuContent(categories: categories, kinds: [.expense]) { category in
                    draft.category = category
                }
            } label: {
                PickerRowLabel(
                    text: draft.category?.name ?? "בחרו קטגוריה",
                    systemImage: draft.category?.symbolName
                )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(
                top: Theme.Spacing.xs,
                leading: 0,
                bottom: Theme.Spacing.xs,
                trailing: 0
            ))
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
