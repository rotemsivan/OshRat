import SwiftUI
import SwiftData

/// Top-level container for the first-launch experience.
///
/// Two phases:
///   1. `WelcomeView` — friendly intro with one "let's start" button.
///   2. The step wizard — personal details → financial accounts → budget.
///
/// All styling — colours, fonts, spacing, card shape — flows from
/// `Theme`. The screen-wide `.tint(Theme.Colors.accent)` brands every
/// toolbar button, picker, and link inside the wizard with the cheese-
/// gold accent without each child view having to know.
struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = OnboardingViewModel()

    /// `false` while the welcome screen is up, `true` once the user has
    /// tapped "let's start" and we've switched to the wizard.
    @State private var hasStarted: Bool = false

    var body: some View {
        Group {
            if hasStarted {
                wizard
                    .transition(.opacity)
            } else {
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        hasStarted = true
                    }
                }
                .transition(.opacity)
            }
        }
        // Brand-tint everything below this point.
        .tint(Theme.Colors.accent)
        // The way back into the admin panel after a wipe: with no profile in
        // the store `ContentView` routes here, and without this the only route
        // to a demo scenario would be finishing the wizard by hand first.
        // `.topTrailing` under RTL is the visual top-left, away from the
        // wizard's own controls.
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            // Wiping from here leaves the wizard holding drafts that point at
            // categories the wipe deleted (a planned expense keeps a `Category`
            // reference), and reading one of those would trap. Starting the
            // wizard over is both the safe answer and the expected one.
            AdminPanelButton {
                viewModel = OnboardingViewModel()
                hasStarted = false
            }
            .padding(.horizontal, Theme.Spacing.sm)
        }
        #endif
    }

    // MARK: - Wizard

    private var wizard: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    StepProgressIndicator(
                        currentIndex: OnboardingStep.allCases.firstIndex(of: viewModel.step) ?? 0,
                        totalSteps: OnboardingStep.allCases.count
                    )
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)

                    Group {
                        switch viewModel.step {
                        case .personalDetails:
                            PersonalDetailsStepView(viewModel: viewModel)
                        case .financialAccounts:
                            AccountsStepView(viewModel: viewModel)
                        case .budget:
                            BudgetStepView(viewModel: viewModel)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
    }

    private var navigationTitle: LocalizedStringKey {
        switch viewModel.step {
        case .personalDetails:   return "פרטים אישיים"
        case .financialAccounts: return "החשבונות שלי"
        case .budget:            return "התקציב החודשי"
        }
    }

    /// Bottom action bar: a "back" button on steps after the first, and
    /// a primary "continue" / "finish" button on the right (which, under
    /// RTL, naturally lands on the leading side of the screen).
    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if viewModel.step != OnboardingStep.allCases.first {
                Button {
                    withAnimation(.easeInOut) {
                        viewModel.retreat()
                    }
                } label: {
                    Text("חזרה")
                        .font(Theme.Typography.sectionTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.xs)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                primaryAction()
            } label: {
                Text(primaryButtonTitle)
                    .font(Theme.Typography.sectionTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canContinue)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
    }

    /// "דילוג וסיום" on an empty budget step, so leaving it blank reads as
    /// the deliberate, allowed choice it is rather than a form left unfinished.
    private var primaryButtonTitle: LocalizedStringKey {
        guard viewModel.isOnLastStep else { return "המשך" }
        return viewModel.step == .budget && viewModel.isBudgetEmpty ? "דילוג וסיום" : "סיום"
    }

    private func primaryAction() {
        if viewModel.isOnLastStep {
            viewModel.commit(into: modelContext)
        } else {
            withAnimation(.easeInOut) {
                viewModel.advance()
            }
        }
    }
}

/// Dot-per-step progress indicator above the wizard. Filled with the
/// brand accent for the current step; muted separator colour for the
/// others.
private struct StepProgressIndicator: View {
    let currentIndex: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Theme.Colors.accent : Theme.Colors.separator)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("שלב \(currentIndex + 1) מתוך \(totalSteps)"))
    }
}

#Preview {
    OnboardingFlowView()
        .modelContainer(for: [UserProfile.self, Account.self, Holding.self, Category.self, Transaction.self, TransactionAttachment.self, BudgetItem.self, Goal.self, FXRateSnapshot.self], inMemory: true)
}
