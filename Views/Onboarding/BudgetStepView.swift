import SwiftUI
import SwiftData

/// Step 3 of the setup wizard: the user's monthly budget.
///
/// Two sections stacked vertically in a single List:
///   * **Income sources** — 1+ named lines (salary, side gig…). At
///     least one is required to continue.
///   * **Planned expenses** — optional, grouped visually by needs vs
///     wants via the design-system colours
///     (`Theme.Colors.expense` for needs, `Theme.Colors.wants` for
///     wants — matches the dashboard).
struct BudgetStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    @Query(sort: \Category.name) private var categories: [Category]

    @State private var editingIncome: IncomeSourceDraft?
    @State private var isEditingNewIncome: Bool = false

    @State private var editingExpense: PlannedExpenseDraft?
    @State private var isEditingNewExpense: Bool = false

    var body: some View {
        List {
            incomeSection
            expensesSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .font(Theme.Typography.body)
        .sheet(item: $editingIncome) { draft in
            IncomeSourceEditorSheet(
                draft: draft,
                isNew: isEditingNewIncome,
                onSave: { saved in
                    if isEditingNewIncome {
                        viewModel.addIncome(saved)
                    } else {
                        viewModel.update(saved)
                    }
                },
                onCancel: {}
            )
        }
        .sheet(item: $editingExpense) { draft in
            PlannedExpenseEditorSheet(
                categories: categories,
                draft: draft,
                isNew: isEditingNewExpense,
                onSave: { saved in
                    if isEditingNewExpense {
                        viewModel.addExpense(saved)
                    } else {
                        viewModel.update(saved)
                    }
                },
                onCancel: {}
            )
        }
    }

    // MARK: - Income

    private var incomeSection: some View {
        Section {
            if viewModel.incomeDrafts.isEmpty {
                Text("הוסיפו לפחות מקור הכנסה אחד כדי שנוכל לחשב לכם תקציב חודשי.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(viewModel.incomeDrafts) { draft in
                    Button {
                        isEditingNewIncome = false
                        editingIncome = draft
                    } label: {
                        IncomeDraftRow(draft: draft)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: viewModel.deleteIncome(at:))
            }

            Button {
                isEditingNewIncome = true
                editingIncome = IncomeSourceDraft(currencyCode: viewModel.preferredCurrencyCode)
            } label: {
                Label("הוספת מקור הכנסה", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.Colors.accent)
            }
        } header: {
            Text("הכנסות")
        } footer: {
            Text("ההכנסות החודשיות הצפויות. אפשר להוסיף כמה שצריך — משכורת, עבודות צד, השכרה.")
        }
    }

    // MARK: - Expenses

    private var expensesSection: some View {
        Section {
            if viewModel.plannedExpenseDrafts.isEmpty {
                Text("לא חובה להגדיר עכשיו. אפשר להוסיף הוצאות מתוכננות בכל עת — נתחיל בדוגמה אחת כדי להבין.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                ForEach(viewModel.plannedExpenseDrafts) { draft in
                    Button {
                        isEditingNewExpense = false
                        editingExpense = draft
                    } label: {
                        PlannedExpenseRow(draft: draft)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: viewModel.deleteExpenses(at:))
            }

            Button {
                isEditingNewExpense = true
                editingExpense = PlannedExpenseDraft(currencyCode: viewModel.preferredCurrencyCode)
            } label: {
                Label("הוספת הוצאה מתוכננת", systemImage: "plus.circle.fill")
                    .foregroundStyle(Theme.Colors.accent)
            }
        } header: {
            Text("הוצאות מתוכננות")
        }
    }
}

// MARK: - Rows

/// Row for an income source. Plain layout — design system colours and
/// the income-green dot tie it visually to the dashboard's monthly
/// summary card.
private struct IncomeDraftRow: View {
    let draft: IncomeSourceDraft

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(Theme.Colors.income)
                .frame(width: 10, height: 10)
            Text(draft.name.isEmpty ? "ללא שם" : draft.name)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text(draft.plannedAmount.formatted(.currency(code: draft.currencyCode)))
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
    }
}

/// Row for a planned expense. Leading dot uses the design system's
/// semantic money colours — expense red for needs, wants orange for
/// wants — to match the dashboard's budget card.
private struct PlannedExpenseRow: View {
    let draft: PlannedExpenseDraft

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            natureBadge

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
                Text(draft.plannedAmount.formatted(.currency(code: draft.currencyCode)))
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .monospacedDigit()
                if draft.frequencyKind == .everyXWeeks {
                    Text("~\(monthlyEquivalent.formatted(.currency(code: draft.currencyCode))) חודשי")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                }
            }
        }
    }

    /// Coloured pill identifying need vs want. Falls back to the muted
    /// separator colour when no category has been picked yet.
    private var natureBadge: some View {
        Circle()
            .fill(badgeColor)
            .frame(width: 10, height: 10)
    }

    private var badgeColor: Color {
        switch draft.category?.nature {
        case .need:    return Theme.Colors.expense
        case .want:    return Theme.Colors.wants
        case .neutral: return Theme.Colors.separator
        case .none:    return Theme.Colors.separator
        }
    }

    private var title: String {
        let categoryName = draft.category?.name ?? "ללא קטגוריה"
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? categoryName : "\(categoryName) — \(note)"
    }

    private var subtitle: String {
        switch draft.frequencyKind {
        case .monthly:     return "חודשי"
        case .everyXWeeks: return "כל \(draft.frequencyWeeks) שבועות"
        }
    }

    private var monthlyEquivalent: Decimal {
        switch draft.frequencyKind {
        case .monthly: return draft.plannedAmount
        case .everyXWeeks:
            let weeks = max(draft.frequencyWeeks, 1)
            return draft.plannedAmount * (Decimal(30) / Decimal(weeks * 7))
        }
    }
}

#Preview {
    BudgetStepView(viewModel: OnboardingViewModel())
        .modelContainer(for: [UserProfile.self, Account.self, Holding.self, Category.self, Transaction.self, BudgetItem.self, Goal.self, FXRateSnapshot.self], inMemory: true)
}
