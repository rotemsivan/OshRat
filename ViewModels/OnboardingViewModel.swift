import Foundation
import SwiftData

/// Drives the first-launch setup wizard.
///
/// While the user is filling things in we keep everything as plain values
/// (a "draft"). Nothing touches SwiftData until the user finishes the last
/// step and we call `commit(into:)`. That way, abandoning the wizard
/// half-way leaves the database clean — no orphan `UserProfile` or `Account`
/// rows to clean up later.
@Observable
final class OnboardingViewModel {

    // MARK: - Personal details (step 1)

    var name: String = ""
    var profession: String = ""
    var goalsText: String = ""
    var preferredCurrencyCode: String = "ILS"

    // MARK: - Financial accounts (step 2)

    var accountDrafts: [AccountDraft] = []

    // MARK: - Wizard state

    var step: OnboardingStep = .personalDetails

    /// Whether the "Continue" button on the current step should be enabled.
    /// Each step has its own minimal requirement; this keeps validation
    /// in one place rather than scattered across views.
    var canContinue: Bool {
        switch step {
        case .personalDetails:
            // A name is the only hard requirement — everything else can be
            // edited later from the settings screen.
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .financialAccounts:
            // We want the dashboard to have *something* to show, so require
            // at least one account. A zero-balance account is fine.
            return !accountDrafts.isEmpty
        }
    }

    /// Whether the current step is the last one — controls whether the
    /// primary button reads "Continue" or "Finish".
    var isOnLastStep: Bool {
        step == OnboardingStep.allCases.last
    }

    // MARK: - Navigation between steps

    func advance() {
        guard let currentIndex = OnboardingStep.allCases.firstIndex(of: step),
              currentIndex + 1 < OnboardingStep.allCases.count
        else { return }
        step = OnboardingStep.allCases[currentIndex + 1]
    }

    func retreat() {
        guard let currentIndex = OnboardingStep.allCases.firstIndex(of: step),
              currentIndex > 0
        else { return }
        step = OnboardingStep.allCases[currentIndex - 1]
    }

    // MARK: - Account draft helpers

    func addAccount(_ draft: AccountDraft) {
        accountDrafts.append(draft)
    }

    func update(_ draft: AccountDraft) {
        guard let index = accountDrafts.firstIndex(where: { $0.id == draft.id }) else { return }
        accountDrafts[index] = draft
    }

    func deleteAccounts(at offsets: IndexSet) {
        // `remove(atOffsets:)` is a SwiftUI extension; doing it by hand here
        // keeps the view model dependency-free. Sort descending so each
        // removal doesn't shift the indices we still have to delete.
        for index in offsets.sorted(by: >) {
            accountDrafts.remove(at: index)
        }
    }

    // MARK: - Persistence

    /// Turns the in-memory drafts into real SwiftData rows. Called once,
    /// when the user taps "Finish" on the last step.
    func commit(into context: ModelContext) {
        let profile = UserProfile(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            profession: profession.trimmingCharacters(in: .whitespacesAndNewlines),
            goalsText: goalsText,
            preferredCurrencyCode: preferredCurrencyCode
        )
        context.insert(profile)

        for draft in accountDrafts {
            let account = Account(
                name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: draft.type,
                balance: draft.balance,
                currencyCode: draft.currencyCode,
                lastUpdated: .now
            )
            context.insert(account)
        }

        // Save explicitly so the gating @Query in ContentView re-fires
        // immediately and the wizard is replaced with the main app.
        try? context.save()
    }
}

/// The discrete steps of the setup wizard, in order.
enum OnboardingStep: CaseIterable {
    case personalDetails
    case financialAccounts
}

/// A draft account being built up in the wizard. We keep this as a plain
/// `struct` (not a SwiftData `@Model`) so that abandoning onboarding
/// doesn't leave half-filled rows in the database.
struct AccountDraft: Identifiable, Hashable {
    let id: UUID
    var name: String
    var type: AccountType
    var balance: Decimal
    var currencyCode: String

    init(
        id: UUID = UUID(),
        name: String = "",
        type: AccountType = .current,
        balance: Decimal = 0,
        currencyCode: String = "ILS"
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.balance = balance
        self.currencyCode = currencyCode
    }
}
