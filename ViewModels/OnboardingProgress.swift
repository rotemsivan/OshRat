import Foundation
import SwiftData

/// A half-finished setup wizard, saved as the user goes so that closing the
/// app mid-way doesn't throw their typing away.
///
/// Deliberately **not** SwiftData: the wizard's whole design is that nothing
/// reaches the store until "סיום" (see `OnboardingViewModel`) — a
/// `UserProfile` row is what routes `ContentView` to the dashboard, and
/// half-made accounts would count toward net worth. So the drafts are saved
/// as a plain JSON value in `UserDefaults` instead, and deleted on commit.
///
/// Budget lines keep their category by **name and kind** rather than by a
/// store reference: a reference to a category that's gone (a debug wipe, a
/// renamed default) would hand back a model that traps when read, where a
/// name that no longer matches just drops that one line.
struct OnboardingProgress: Codable, Equatable {
    var step: OnboardingStep
    var name: String
    var profession: String
    var goalsText: String
    var preferredCurrencyCode: String
    var accounts: [AccountDraft]
    var incomes: [IncomeSourceDraft]
    var expenses: [SavedExpense]

    /// A `PlannedExpenseDraft` with its category written down by name.
    struct SavedExpense: Codable, Equatable {
        var id: UUID
        var categoryName: String?
        var categoryKind: TransactionKind?
        var note: String
        var plannedAmount: Decimal
        var currencyCode: String
        var schedule: BudgetSchedule
    }

    /// Whether there's anything to come back to. Tapping "בוא נתחיל" and
    /// quitting on an empty first step isn't progress worth a "continue"
    /// button.
    var isWorthResuming: Bool {
        step != .personalDetails
            || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !profession.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !goalsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !accounts.isEmpty || !incomes.isEmpty || !expenses.isEmpty
    }

    /// 1-based, for "שלב 2 מתוך 3".
    var stepNumber: Int {
        (OnboardingStep.allCases.firstIndex(of: step) ?? 0) + 1
    }
}

/// Where `OnboardingProgress` lives between launches.
///
/// `UserDefaults` rather than a file: it's one small value, written on every
/// edit, and cleared once — the same home as the app's other small per-device
/// state. It's on-device only, like everything else the app stores.
enum OnboardingProgressStore {
    static let key = "onboardingProgress"

    static func load(from defaults: UserDefaults = .standard) -> OnboardingProgress? {
        guard let data = defaults.data(forKey: key) else { return nil }
        // A snapshot from an older build whose drafts have since gained a
        // field won't decode. Starting over is the honest outcome — better
        // than guessing at half a draft.
        return try? JSONDecoder().decode(OnboardingProgress.self, from: data)
    }

    static func save(_ progress: OnboardingProgress, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: key)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

extension OnboardingViewModel {
    /// Everything the user has entered so far, as a saveable value. Compared
    /// by the wizard to save only when something actually changed.
    var progress: OnboardingProgress {
        OnboardingProgress(
            step: step,
            name: name,
            profession: profession,
            goalsText: goalsText,
            preferredCurrencyCode: preferredCurrencyCode,
            accounts: accountDrafts,
            incomes: incomeDrafts,
            expenses: plannedExpenseDrafts.map { draft in
                OnboardingProgress.SavedExpense(
                    id: draft.id,
                    categoryName: draft.category?.name,
                    categoryKind: draft.category?.kind,
                    note: draft.note,
                    plannedAmount: draft.plannedAmount,
                    currencyCode: draft.currencyCode,
                    schedule: draft.schedule
                )
            }
        )
    }

    /// Puts a saved wizard back, step included.
    ///
    /// - Parameter categories: the store's categories, to turn each budget
    ///   line's saved category name back into the row. A line whose category
    ///   can't be found is dropped rather than restored without one — the
    ///   editor wouldn't let it be saved that way, and `commit` would skip it.
    func restore(_ progress: OnboardingProgress, categories: [Category]) {
        step = progress.step
        name = progress.name
        profession = progress.profession
        goalsText = progress.goalsText
        preferredCurrencyCode = progress.preferredCurrencyCode
        accountDrafts = progress.accounts
        incomeDrafts = progress.incomes
        plannedExpenseDrafts = progress.expenses.compactMap { saved in
            guard let category = categories.first(where: {
                $0.name == saved.categoryName && $0.kind == saved.categoryKind
            }) else { return nil }
            return PlannedExpenseDraft(
                id: saved.id,
                category: category,
                note: saved.note,
                plannedAmount: saved.plannedAmount,
                currencyCode: saved.currencyCode,
                schedule: saved.schedule
            )
        }
    }
}
