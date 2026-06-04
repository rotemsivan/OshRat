import SwiftUI
import SwiftData

/// Top-level container for the first-launch experience.
///
/// Two phases:
///   1. `WelcomeView` — friendly intro with one "let's start" button.
///   2. The step wizard — personal details → financial accounts → finish.
///
/// We keep both phases inside this single view so the welcome screen can
/// fade smoothly into the wizard, and because the parent (`ContentView`)
/// only cares about one thing: "has the user finished onboarding yet?".
struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext

    /// Owns the wizard's draft state. `@State` is the @Observable-era
    /// way to give a view ownership of a reference-type model.
    @State private var viewModel = OnboardingViewModel()

    /// `false` while the welcome screen is up, `true` once the user has
    /// tapped "let's start" and we've switched to the wizard.
    @State private var hasStarted: Bool = false

    var body: some View {
        Group {
            if hasStarted {
                wizard
            } else {
                WelcomeView {
                    withAnimation(.easeInOut) {
                        hasStarted = true
                    }
                }
            }
        }
    }

    // MARK: - Wizard

    /// The multi-step wizard, wrapped in a `NavigationStack` so each step
    /// gets a real title and toolbar without us hand-rolling chrome.
    private var wizard: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StepProgressIndicator(
                    currentIndex: OnboardingStep.allCases.firstIndex(of: viewModel.step) ?? 0,
                    totalSteps: OnboardingStep.allCases.count
                )
                .padding(.horizontal)
                .padding(.top, 8)

                // Swap the body of the current step. The transition makes
                // the change feel like forward/back movement rather than
                // a hard cut.
                Group {
                    switch viewModel.step {
                    case .personalDetails:
                        PersonalDetailsStepView(viewModel: viewModel)
                    case .financialAccounts:
                        AccountsStepView(viewModel: viewModel)
                    }
                }
                .transition(.opacity)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
    }

    /// Title for the current step. Kept as plain strings (which SwiftUI
    /// treats as LocalizedStringKey) rather than building one big switch
    /// in the body.
    private var navigationTitle: LocalizedStringKey {
        switch viewModel.step {
        case .personalDetails:   return "פרטים אישיים"
        case .financialAccounts: return "החשבונות שלי"
        }
    }

    /// Bottom action bar: a "back" button on steps after the first, and
    /// a primary "continue" / "finish" button on the right (which, under
    /// RTL, naturally lands on the leading side of the screen).
    private var bottomBar: some View {
        HStack(spacing: 12) {
            if viewModel.step != OnboardingStep.allCases.first {
                Button {
                    withAnimation(.easeInOut) {
                        viewModel.retreat()
                    }
                } label: {
                    Text("חזרה")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                primaryAction()
            } label: {
                Text(viewModel.isOnLastStep ? "סיום" : "המשך")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canContinue)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    /// "Continue" advances to the next step; on the last step it instead
    /// commits the drafts into SwiftData, which (via the @Query in
    /// ContentView) tears down this whole view.
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

/// A tiny dot-per-step progress indicator above the wizard. Filled circle
/// for the current step, hollow circles for the others.
private struct StepProgressIndicator: View {
    let currentIndex: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("שלב \(currentIndex + 1) מתוך \(totalSteps)"))
    }
}

#Preview {
    OnboardingFlowView()
        .modelContainer(for: [UserProfile.self, Account.self, Category.self, Transaction.self, BudgetItem.self, Goal.self], inMemory: true)
        .environment(\.layoutDirection, .rightToLeft)
}
