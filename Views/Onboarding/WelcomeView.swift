import SwiftUI

/// First-launch hero screen — `BrandHeroLayout` with the way into setup.
///
/// When a half-finished setup was saved (`OnboardingProgress`), the screen
/// greets the user back instead: the main button continues where they left
/// off, and starting over is a quieter button behind a confirmation, since it
/// throws their typing away.
///
/// On a device joining an iCloud account that already has data
/// (`isWaitingForCloud`), it says so and waits for the sync instead of
/// offering setup — `ContentView` moves on by itself the moment the synced
/// profile arrives. "להתחיל בכל זאת" is there for the case it never does.
struct WelcomeView: View {
    /// A setup the user left half-way, or `nil` on a genuine first launch.
    var savedProgress: OnboardingProgress? = nil
    let onStart: () -> Void
    /// Continue the saved setup. Only used when `savedProgress` is set.
    var onResume: () -> Void = {}
    /// Discard the saved setup; the screen then offers a fresh start.
    var onStartOver: () -> Void = {}
    /// iCloud holds this user's data from another device; it's syncing in.
    var isWaitingForCloud = false
    /// The wait has run long — say so, so "להתחיל בכל זאת" reads as a real
    /// option rather than giving up.
    var isCloudWaitSlow = false
    /// Stop waiting and set up this device from scratch anyway.
    var onSkipCloudWait: () -> Void = {}

    @State private var isConfirmingStartOver = false

    /// Set the moment the main button is tapped; also holds the start-over
    /// button off while the screen hands over to the wizard.
    @State private var didTapStart = false

    var body: some View {
        BrandHeroLayout(subtitle: subtitle) {
            if isWaitingForCloud {
                cloudWait
            } else {
                setupActions
            }
        }
        .alert(Text("להתחיל את ההגדרה מחדש?"), isPresented: $isConfirmingStartOver) {
            Button("התחלה מחדש", role: .destructive, action: startOver)
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("מה שמילאת עד עכשיו יימחק.")
        }
    }

    /// Instead of the setup buttons while another device's data syncs in.
    @ViewBuilder
    private var cloudWait: some View {
        ProgressView()
            .controlSize(.large)
            .tint(Theme.Colors.accent)
        Text(isCloudWaitSlow
             ? "זה לוקח יותר מהרגיל. אפשר להמשיך לחכות, או להתחיל כאן מההתחלה."
             : "הנתונים שלך מ-iCloud בדרך — זה ייקח רגע.")
            .font(Theme.Typography.bodySmall)
            .foregroundStyle(Theme.Colors.textSecondary)
            .multilineTextAlignment(.center)
        Button("להתחיל בכל זאת", action: onSkipCloudWait)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(minHeight: 44)
    }

    @ViewBuilder
    private var setupActions: some View {
        if let savedProgress {
            Text("שמרנו את מה שמילאת · שלב \(savedProgress.stepNumber) מתוך \(OnboardingStep.allCases.count)")
                .font(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }

        HeroPrimaryButton(
            savedProgress == nil ? "בוא נתחיל" : "המשך בהגדרה",
            isPressed: $didTapStart,
            action: savedProgress == nil ? onStart : onResume
        )

        if savedProgress != nil {
            Button("להתחיל מחדש", action: confirmStartOver)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(minHeight: 44)
                .disabled(didTapStart)
        }
    }

    private func confirmStartOver() {
        isConfirmingStartOver = true
    }

    private func startOver() {
        withAnimation(.easeInOut(duration: 0.25)) {
            onStartOver()
        }
    }

    /// The tagline, or a welcome back — by name when the saved setup has one.
    /// "טוב לראות אותך שוב" reads the same for any reader, which a
    /// "ברוך שובך" wouldn't.
    private var subtitle: String {
        if isWaitingForCloud { return String(localized: "מצאנו את הנתונים שלך ב-iCloud") }
        guard let savedProgress else { return String(localized: "ניהול תקציב אישי, פשוט ופרטי.") }
        let name = savedProgress.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty
            ? String(localized: "טוב לראות אותך שוב")
            : String(localized: "טוב לראות אותך שוב, \(name)")
    }
}

#Preview {
    WelcomeView(onStart: {})
}
