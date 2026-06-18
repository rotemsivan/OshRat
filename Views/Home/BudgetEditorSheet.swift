import SwiftUI
import SwiftData

/// Post-onboarding budget editor. Lets the user revisit every budget
/// line they entered during the wizard — add new ones, tweak amounts,
/// fix categories, delete what no longer applies. Reachable from the
/// pencil button on `BudgetSummaryCard`.
///
/// Structure mirrors `BudgetStepView`: a single `List` with two
/// sections (income → expenses), each row tap-to-edit, swipe-to-delete,
/// and a trailing "+ הוסף" button. Editing reuses the same per-line
/// sheets as onboarding (`IncomeSourceEditorSheet`,
/// `PlannedExpenseEditorSheet`) so behavior is identical between the
/// two entry points — including validation rules like "income needs a
/// name" and "expense needs a category".
///
/// Unlike the wizard, this sheet writes straight to SwiftData rather
/// than through draft structs: there's no "finish" step to commit
/// against, and every save here is a discrete user action.
struct BudgetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \BudgetItem.name) private var budgetItems: [BudgetItem]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query private var profiles: [UserProfile]

    /// Selected income line being edited (or a fresh draft when adding).
    /// `pendingIncomeItem` tracks the SwiftData row the draft maps back
    /// to — nil means "new line, insert on save".
    @State private var editingIncome: IncomeSourceDraft?
    @State private var pendingIncomeItem: BudgetItem?

    @State private var editingExpense: PlannedExpenseDraft?
    @State private var pendingExpenseItem: BudgetItem?

    var body: some View {
        NavigationStack {
            List {
                incomeSection
                expensesSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .font(Theme.Typography.body)
            .navigationTitle(Text("עריכת התקציב"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
            .sheet(item: $editingIncome) { draft in
                IncomeSourceEditorSheet(
                    draft: draft,
                    isNew: pendingIncomeItem == nil,
                    onSave: { saved in saveIncome(saved) },
                    onCancel: {}
                )
            }
            .sheet(item: $editingExpense) { draft in
                PlannedExpenseEditorSheet(
                    categories: categories,
                    draft: draft,
                    isNew: pendingExpenseItem == nil,
                    onSave: { saved in saveExpense(saved) },
                    onCancel: {}
                )
            }
        }
        .tint(Theme.Colors.accent)
    }

    // MARK: - Sections

    private var incomeSection: some View {
        Section {
            if incomeItems.isEmpty {
                Text("עדיין לא הוגדרה הכנסה.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(incomeItems) { item in
                    Button {
                        pendingIncomeItem = item
                        editingIncome = IncomeSourceDraft(from: item)
                    } label: {
                        IncomeItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteIncome(at:))
            }

            Button {
                pendingIncomeItem = nil
                editingIncome = IncomeSourceDraft(currencyCode: preferredCurrencyCode)
            } label: {
                Label("הוספת מקור הכנסה", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.Colors.accent)
            }
        } header: {
            Text("הכנסות")
        }
    }

    private var expensesSection: some View {
        Section {
            if expenseItems.isEmpty {
                Text("עדיין לא הוגדרו הוצאות מתוכננות.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(expenseItems) { item in
                    Button {
                        pendingExpenseItem = item
                        editingExpense = PlannedExpenseDraft(from: item)
                    } label: {
                        ExpenseItemRow(item: item)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteExpense(at:))
            }

            Button {
                pendingExpenseItem = nil
                editingExpense = PlannedExpenseDraft(currencyCode: preferredCurrencyCode)
            } label: {
                Label("הוספת הוצאה מתוכננת", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.Colors.accent)
            }
        } header: {
            Text("הוצאות מתוכננות")
        }
    }

    // MARK: - Derived data

    private var incomeItems: [BudgetItem] {
        budgetItems.filter { $0.kind == .income }
    }

    private var expenseItems: [BudgetItem] {
        budgetItems.filter { $0.kind == .expense }
    }

    private var preferredCurrencyCode: String {
        profiles.first?.preferredCurrencyCode ?? "ILS"
    }

    // MARK: - Persistence

    private func saveIncome(_ draft: IncomeSourceDraft) {
        if let existing = pendingIncomeItem {
            draft.apply(to: existing)
        } else {
            let item = BudgetItem(kind: .income)
            draft.apply(to: item)
            modelContext.insert(item)
        }
        pendingIncomeItem = nil
        try? modelContext.save()
    }

    private func saveExpense(_ draft: PlannedExpenseDraft) {
        if let existing = pendingExpenseItem {
            draft.apply(to: existing)
        } else {
            let item = BudgetItem(kind: .expense)
            draft.apply(to: item)
            modelContext.insert(item)
        }
        pendingExpenseItem = nil
        try? modelContext.save()
    }

    private func deleteIncome(at offsets: IndexSet) {
        // Resolve indices against the filtered array we displayed, so
        // a delete here doesn't accidentally remove the wrong row from
        // the broader budgetItems query.
        let items = incomeItems
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
            try? modelContext.save()
        }
    }

    private func deleteExpense(at offsets: IndexSet) {
        let items = expenseItems
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
            try? modelContext.save()
        }
    }
}

// MARK: - Rows

/// Income line row — green dot + name on the leading edge, monthly
/// amount on the trailing edge. Mirrors `IncomeDraftRow` in
/// `BudgetStepView` so the two surfaces read the same.
private struct IncomeItemRow: View {
    let item: BudgetItem

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(Theme.Colors.income)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.isEmpty ? "ללא שם" : item.name)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                // Only surface the cadence when it's something other than a
                // plain "every month" line, so common salaries stay quiet.
                if showsSchedule {
                    Text(item.scheduleDescription)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer()
            Text(item.plannedAmount.formatted(.currency(code: item.currencyCode)))
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }

    private var showsSchedule: Bool {
        item.hasNoteworthySchedule
    }
}

/// Expense line row — coloured dot (need/want), category + optional
/// note, amount with a monthly-equivalent caption for non-monthly
/// cadences. Mirrors `PlannedExpenseRow` in `BudgetStepView`.
private struct ExpenseItemRow: View {
    let item: BudgetItem

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(badgeColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.plannedAmount.formatted(.currency(code: item.currencyCode)))
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .monospacedDigit()
                if !item.isOneTime, item.recurrenceUnit.isAveraged {
                    Text("~\(item.monthlyEquivalent.formatted(.currency(code: item.currencyCode))) חודשי")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var badgeColor: Color {
        switch item.category?.nature {
        case .need:    return Theme.Colors.expense
        case .want:    return Theme.Colors.wants
        case .neutral: return Theme.Colors.separator
        case .none:    return Theme.Colors.separator
        }
    }

    private var title: String {
        let categoryName = item.category?.name ?? "ללא קטגוריה"
        let note = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? categoryName : "\(categoryName) — \(note)"
    }

    private var subtitle: String {
        item.scheduleDescription
    }
}

#Preview {
    BudgetEditorSheet()
        .modelContainer(
            for: [
                UserProfile.self, Account.self, Holding.self, Category.self,
                Transaction.self, BudgetItem.self, Goal.self, FXRateSnapshot.self
            ],
            inMemory: true
        )
}
