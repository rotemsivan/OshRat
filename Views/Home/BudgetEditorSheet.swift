import SwiftUI
import SwiftData

/// Post-onboarding budget editor. Lets the user revisit every budget
/// line they entered during the wizard — add new ones, tweak amounts,
/// fix categories, delete what no longer applies. Reachable from the
/// pencil button on `BudgetVsActualCard`.
///
/// A single `List`: income first, then the expenses nested the way a budget
/// is read — צרכים / מותרות / אחר, each category a collapsible group (closed
/// to start, so the list is short at a glance) with its monthly total, and
/// its lines inside (`BudgetLineGroups`). Rows are tap-to-edit and
/// swipe-to-delete, and each section ends with a "+ הוסף" button. Editing reuses the same per-line
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
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Query(sort: \FXRateSnapshot.fetchedAt, order: .reverse) private var fxSnapshots: [FXRateSnapshot]

    /// Selected income line being edited (or a fresh draft when adding).
    /// `pendingIncomeItem` tracks the SwiftData row the draft maps back
    /// to — nil means "new line, insert on save".
    @State private var editingIncome: IncomeSourceDraft?
    @State private var pendingIncomeItem: BudgetItem?

    @State private var editingExpense: PlannedExpenseDraft?
    @State private var pendingExpenseItem: BudgetItem?

    /// The category groups the user has opened (`BudgetLineGroups.CategoryGroup.id`).
    /// Empty to start: every category closed.
    @State private var expandedCategories: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                incomeSection
                expenseSections
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
                    .accessibilityHint(Text("הקש לעריכה"))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        // Trash icon + full swipe to delete — the same
                        // delete gesture used across the accounts and
                        // transactions lists.
                        Button(role: .destructive) {
                            deleteIncome(item)
                        } label: {
                            Image(systemName: "trash")
                        }.tint(.red)
                        .accessibilityLabel(Text("מחיקה"))
                    }
                }
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

    /// One section per bucket (needs, wants, other), each category a
    /// collapsible group. Drawn from value snapshots: a deleted line is gone
    /// from the store at once, while its row is still animating out.
    @ViewBuilder
    private var expenseSections: some View {
        let groups = expenseGroups
        if groups.sections.isEmpty {
            Section {
                Text("עדיין לא הוגדרו הוצאות מתוכננות.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                addExpenseButton
            } header: {
                Text("הוצאות מתוכננות")
            }
        } else {
            ForEach(groups.sections) { section in
                Section {
                    ForEach(section.groups) { group in
                        DisclosureGroup(isExpanded: expansion(of: group.id)) {
                            ForEach(group.lines) { line in
                                expenseLineRow(line)
                            }
                        } label: {
                            CategoryGroupLabel(group: group, currencyCode: preferredCurrencyCode)
                        }
                    }
                    // The add button closes the last section, as it did the
                    // single expenses section before.
                    if section.id == groups.sections.last?.id {
                        addExpenseButton
                    }
                } header: {
                    BucketHeader(bucket: section.bucket, total: section.monthlyTotal, currencyCode: preferredCurrencyCode)
                } footer: {
                    if section.id == groups.sections.last?.id, groups.fxUnavailable {
                        Text("חלק מהסכומים לא נספרו — אין שער חליפין עדכני.")
                    }
                }
            }
        }
    }

    private func expenseLineRow(_ line: BudgetLineGroups.Line) -> some View {
        Button {
            guard let item = budgetItem(line.id) else { return }
            pendingExpenseItem = item
            editingExpense = PlannedExpenseDraft(from: item)
        } label: {
            ExpenseLineRow(line: line)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("הקש לעריכה"))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                if let item = budgetItem(line.id) { deleteExpense(item) }
            } label: {
                Image(systemName: "trash")
            }.tint(.red)
            .accessibilityLabel(Text("מחיקה"))
        }
    }

    private var addExpenseButton: some View {
        Button {
            pendingExpenseItem = nil
            editingExpense = PlannedExpenseDraft(currencyCode: preferredCurrencyCode)
        } label: {
            Label("הוספת הוצאה מתוכננת", systemImage: "plus.circle.fill")
                .foregroundStyle(Theme.Colors.accent)
        }
    }

    private func expansion(of groupID: String) -> Binding<Bool> {
        Binding(
            get: { expandedCategories.contains(groupID) },
            set: { isOpen in
                if isOpen { expandedCategories.insert(groupID) } else { expandedCategories.remove(groupID) }
            }
        )
    }

    // MARK: - Derived data

    private var incomeItems: [BudgetItem] {
        budgetItems.filter { $0.kind == .income }
    }

    private var expenseGroups: BudgetLineGroups {
        BudgetLineGroups(items: budgetItems, preferredCurrency: preferredCurrencyCode, fxSnapshot: fxSnapshots.first)
    }

    /// The live model behind a snapshot row, looked up only when acting on it.
    private func budgetItem(_ id: PersistentIdentifier) -> BudgetItem? {
        budgetItems.first { $0.persistentModelID == id }
    }

    private var preferredCurrencyCode: String {
        profiles.first?.preferredCurrencyCode ?? "ILS"
    }

    // MARK: - Persistence

    /// Every budget change goes through `BudgetCommitmentService.change`, so
    /// this month's plan is written down before it and can only tighten after
    /// it — the budget achievements judge the month against that.
    private func saveIncome(_ draft: IncomeSourceDraft) {
        BudgetCommitmentService.change(in: modelContext) {
            if let existing = pendingIncomeItem {
                draft.apply(to: existing)
            } else {
                let item = BudgetItem(kind: .income)
                draft.apply(to: item)
                modelContext.insert(item)
            }
        }
        pendingIncomeItem = nil
    }

    private func saveExpense(_ draft: PlannedExpenseDraft) {
        var saved: BudgetItem?
        BudgetCommitmentService.change(in: modelContext) {
            if let existing = pendingExpenseItem {
                draft.apply(to: existing)
                saved = existing
            } else {
                let item = BudgetItem(kind: .expense)
                draft.apply(to: item)
                modelContext.insert(item)
                saved = item
            }
        }
        pendingExpenseItem = nil
        // Open the line's category, so a new line — or one moved to another
        // category — is in view where it landed rather than in a closed group.
        if let saved, let groupID = BudgetLineGroups(
            items: [saved], preferredCurrency: preferredCurrencyCode, fxSnapshot: nil
        ).groupID(containing: saved.persistentModelID) {
            expandedCategories.insert(groupID)
        }
    }

    private func deleteIncome(_ item: BudgetItem) {
        withAnimation {
            BudgetCommitmentService.change(in: modelContext) {
                modelContext.delete(item)
                // A deleted line changes the month's plan; the budget
                // achievements need to know even though the row is gone.
                ProgressService.recordBudgetLineDeleted(in: modelContext)
            }
        }
    }

    private func deleteExpense(_ item: BudgetItem) {
        withAnimation {
            BudgetCommitmentService.change(in: modelContext) {
                modelContext.delete(item)
                // A deleted line changes the month's plan; the budget
                // achievements need to know even though the row is gone.
                ProgressService.recordBudgetLineDeleted(in: modelContext)
            }
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

/// A bucket's header: its name, and its monthly total on the trailing edge.
private struct BucketHeader: View {
    let bucket: BudgetLineGroups.Bucket
    let total: Decimal
    let currencyCode: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if total > 0 {
                Text("\(total.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))) לחודש")
                    .monospacedDigit()
            }
        }
    }

    private var title: LocalizedStringKey {
        switch bucket {
        case .needs: return "צרכים"
        case .wants: return "מותרות"
        case .other: return "אחר"
        }
    }
}

/// A category's row: its glyph in its colour, name, how many lines, and the
/// monthly total. The `DisclosureGroup` around it adds the chevron.
private struct CategoryGroupLabel: View {
    let group: BudgetLineGroups.CategoryGroup
    let currencyCode: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: group.symbolName)
                .foregroundStyle(Color(hex: group.colorHex))
                .frame(width: 28)
            Text(group.name ?? String(localized: "ללא קטגוריה"))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            // A badge rather than "· N": a separator glyph beside a number
            // lands on the wrong side of it in right-to-left text.
            Text(group.lines.count, format: .number)
                .font(Theme.Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.Colors.separator))
                .accessibilityLabel(Text("\(group.lines.count) פריטים"))
            Spacer()
            if group.monthlyTotal > 0 {
                Text(group.monthlyTotal.formatted(.currency(code: currencyCode).precision(.fractionLength(0))))
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One budget line inside its category: its note (or schedule), the schedule
/// underneath, and the amount with a monthly figure for sub-monthly cadences.
private struct ExpenseLineRow: View {
    let line: BudgetLineGroups.Line

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let subtitle = line.subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(line.amount.formatted(.currency(code: line.currencyCode)))
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .monospacedDigit()
                if let monthly = line.averagedMonthly {
                    Text("~\(monthly.formatted(.currency(code: line.currencyCode))) חודשי")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

#Preview {
    BudgetEditorSheet()
        .modelContainer(
            for: [
                UserProfile.self, Account.self, Holding.self, Category.self,
                Transaction.self, TransactionAttachment.self, BudgetItem.self, Goal.self, FXRateSnapshot.self
            ],
            inMemory: true
        )
}
