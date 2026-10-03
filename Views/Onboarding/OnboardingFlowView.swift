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

    /// A setup the user left half-way on an earlier launch, if it's worth
    /// offering back. Read once, when the wizard first appears.
    @State private var savedProgress: OnboardingProgress? =
        OnboardingProgressStore.load().flatMap { $0.isWorthResuming ? $0 : nil }

    /// This iCloud account already has data from another device, syncing in
    /// — the welcome screen waits for it instead of offering setup, so the
    /// user doesn't end up with a second profile and duplicate accounts.
    @State private var isWaitingForCloud = false
    /// The wait has gone on long enough to say so.
    @State private var isCloudWaitSlow = false

    /// How often the wait re-checks iCloud, and when it calls itself slow.
    private static let cloudRecheckInterval: Duration = .seconds(5)
    private static let cloudSlowAfter: Duration = .seconds(45)

    var body: some View {
        Group {
            if hasStarted {
                wizard
                    .transition(.opacity)
            } else {
                WelcomeView(
                    savedProgress: savedProgress,
                    onStart: {
                        // A fresh start replaces whatever was saved before.
                        OnboardingProgressStore.clear()
                        enterWizard()
                    },
                    onResume: resume,
                    onStartOver: {
                        OnboardingProgressStore.clear()
                        savedProgress = nil
                    },
                    isWaitingForCloud: isWaitingForCloud,
                    isCloudWaitSlow: isCloudWaitSlow,
                    onSkipCloudWait: stopWaitingForCloud
                )
                .transition(.opacity)
                .task(checkForCloudData)
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
                OnboardingProgressStore.clear()
                savedProgress = nil
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
        // Saved on every change, so closing the app at any point keeps what
        // was typed. `progress` is a value, so an unchanged wizard writes
        // nothing. (A form still open in an editor sheet isn't in the view
        // model yet, so that one sheet's typing isn't covered.)
        .onChange(of: viewModel.progress) { _, progress in
            OnboardingProgressStore.save(progress)
        }
    }

    /// Only on a genuine first launch — a half-finished setup on this device
    /// means the user is already setting it up here.
    private func checkForCloudData() async {
        guard savedProgress == nil else { return }
        #if DEBUG
        if LaunchArguments.contains("-demoCloudWait") {
            isWaitingForCloud = true
            return
        }
        #endif
        guard await CloudAccountService.hasExistingData() else { return }
        withAnimation { isWaitingForCloud = true }

        // Keep checking while waiting. The profile arriving ends this by
        // itself (`ContentView` swaps onboarding out, cancelling the task).
        // But the data can also *leave*: after a reset on this device, its
        // deletions are still on their way up to iCloud when the first check
        // runs, so it sees a profile that is about to disappear — and a wait
        // that never re-checked would spin forever.
        let clock = ContinuousClock()
        let started = clock.now
        while isWaitingForCloud {
            do { try await Task.sleep(for: Self.cloudRecheckInterval) } catch { return }
            guard await CloudAccountService.hasExistingData() else {
                stopWaitingForCloud()
                return
            }
            if !isCloudWaitSlow, clock.now - started >= Self.cloudSlowAfter {
                withAnimation { isCloudWaitSlow = true }
            }
        }
    }

    private func stopWaitingForCloud() {
        withAnimation {
            isWaitingForCloud = false
            isCloudWaitSlow = false
        }
    }

    private func enterWizard() {
        withAnimation(.easeInOut(duration: 0.4)) {
            hasStarted = true
        }
    }

    /// Put the saved wizard back — step included — and go straight to it.
    private func resume() {
        guard let savedProgress else {
            enterWizard()
            return
        }
        let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        viewModel.restore(savedProgress, categories: categories)
        enterWizard()
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
                        .font(Theme.Typography.amount)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                primaryAction()
            } label: {
                Text(primaryButtonTitle)
                    // `amount` (bold 18) like the welcome screen's button:
                    // the step's content is the focus, not the buttons.
                    .font(Theme.Typography.amount)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
        // The button stays tappable so a tap can show *what's* missing
        // rather than just sitting greyed out.
        guard viewModel.canContinue else {
            viewModel.showsMissingFields = true
            MissingFields.signalRefusedSave()
            return
        }
        if viewModel.isOnLastStep {
            viewModel.commit(into: modelContext)
            // Everything is in the store now; nothing left to resume.
            OnboardingProgressStore.clear()
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
        .modelContainer(for: OshRatSchema.models, inMemory: true)
}
