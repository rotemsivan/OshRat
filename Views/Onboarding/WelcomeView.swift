import SwiftUI

/// First-launch hero screen.
///
/// Reads from the design system end-to-end: the brand accent backs the
/// hero icon, `screenTitle` typography sets the app name, and the
/// primary CTA picks up `Colors.accent` via the screen-wide tint.
///
/// Choreography on appear: the mascot pops in first
/// (see `WelcomeMascotView`), then the title block and the CTA fade-slide
/// up behind it on staggered delays. All three are driven by the single
/// `showsContent` flip, so they can never drift out of sync.
///
/// When a half-finished setup was saved (`OnboardingProgress`), the screen
/// greets the user back instead: the main button continues where they left
/// off, and starting over is a quieter button behind a confirmation, since it
/// throws their typing away.
struct WelcomeView: View {
    /// A setup the user left half-way, or `nil` on a genuine first launch.
    var savedProgress: OnboardingProgress? = nil
    let onStart: () -> Void
    /// Continue the saved setup. Only used when `savedProgress` is set.
    var onResume: () -> Void = {}
    /// Discard the saved setup; the screen then offers a fresh start.
    var onStartOver: () -> Void = {}

    @State private var isConfirmingStartOver = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Drives the small "press" bounce and the haptic trigger. Flipped
    /// to `true` the moment the user taps the CTA; we then wait long
    /// enough for the spring to be visible before handing off to
    /// `onStart`, which kicks off the cross-fade into the wizard.
    @State private var didTapStart: Bool = false

    /// One-shot entrance flag for the text + CTA stagger.
    @State private var showsContent: Bool = false

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                WelcomeMascotView()

                VStack(alignment: .center, spacing: Theme.Spacing.sm) {
                    Text("עכבר עו״ש")
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(subtitle)
                        .font(Theme.Typography.sectionTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .opacity(showsContent ? 1 : 0)
                .offset(y: showsContent || reduceMotion ? 0 : 14)
                .animation(entranceAnimation.delay(0.3), value: showsContent)

                Spacer()

                VStack(spacing: Theme.Spacing.sm) {
                    if let savedProgress {
                        Text("שמרנו את מה שמילאת · שלב \(savedProgress.stepNumber) מתוך \(OnboardingStep.allCases.count)")
                            .font(Theme.Typography.bodySmall)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        handleStart(savedProgress == nil ? onStart : onResume)
                    } label: {
                        Text(savedProgress == nil ? "בוא נתחיל" : "המשך בהגדרה")
                            .font(Theme.Typography.sectionTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.Colors.accent)
                    .scaleEffect(didTapStart ? 1.06 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.55), value: didTapStart)
                    .sensoryFeedback(.impact(weight: .medium), trigger: didTapStart)
                    .disabled(didTapStart)

                    if savedProgress != nil {
                        Button("להתחיל מחדש") {
                            isConfirmingStartOver = true
                        }
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(minHeight: 44)
                        .disabled(didTapStart)
                    }
                }
                .opacity(showsContent ? 1 : 0)
                .offset(y: showsContent || reduceMotion ? 0 : 14)
                .animation(entranceAnimation.delay(0.5), value: showsContent)
            }
            .padding(Theme.Spacing.lg)
        }
        .onAppear { showsContent = true }
        .alert(Text("להתחיל את ההגדרה מחדש?"), isPresented: $isConfirmingStartOver) {
            Button("התחלה מחדש", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    onStartOver()
                }
            }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("מה שמילאת עד עכשיו יימחק.")
        }
    }

    /// The tagline, or a welcome back — by name when the saved setup has one.
    /// "טוב לראות אותך שוב" reads the same for any reader, which a
    /// "ברוך שובך" wouldn't.
    private var subtitle: String {
        guard let savedProgress else { return String(localized: "ניהול תקציב אישי, פשוט ופרטי.") }
        let name = savedProgress.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty
            ? String(localized: "טוב לראות אותך שוב")
            : String(localized: "טוב לראות אותך שוב, \(name)")
    }

    /// Reduce Motion keeps the timing but drops the slide, leaving an
    /// opacity-only fade (the `offset` above is already pinned to 0).
    private var entranceAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.4)
            : .spring(response: 0.5, dampingFraction: 0.8)
    }

    /// Two beats: bounce + haptic, then hand control to the parent so
    /// it can cross-fade into the wizard. The 220 ms delay matches the
    /// spring's perceived peak so the user actually sees the squish.
    private func handleStart(_ action: @escaping () -> Void) {
        didTapStart = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            action()
        }
    }
}

#Preview {
    WelcomeView(onStart: {})
}
