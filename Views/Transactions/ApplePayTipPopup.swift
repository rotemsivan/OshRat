import SwiftUI

/// A card over the new-transaction sheet suggesting the Apple Pay shortcut
/// (`ApplePaySetupView`) — the one feature that makes this sheet fill itself,
/// and one nobody finds on their own, since it lives in the Shortcuts app.
///
/// A custom card rather than an `.alert`: an alert can't hold the
/// "אל תראה לי שוב" toggle. The toggle is only applied when the card closes,
/// by either button or a tap outside, so flipping it doesn't make the card
/// vanish under the user's finger. When and whether it's offered is decided
/// by `NewTransactionSheet` (see `ApplePayTip`).
struct ApplePayTipPopup: View {
    /// "איך מגדירים" — open the setup guide.
    let onSetUp: (_ dontShowAgain: Bool) -> Void
    /// "לא עכשיו", or a tap outside the card.
    let onDismiss: (_ dontShowAgain: Bool) -> Void

    @State private var dontShowAgain = false
    @AccessibilityFocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Dims the form behind, and closes the card like "לא עכשיו".
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onDismiss(dontShowAgain) }
                .accessibilityHidden(true)

            card
                .padding(.horizontal, Theme.Spacing.lg)
        }
    }

    private var card: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "wave.3.right.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityHidden(true)

            VStack(spacing: Theme.Spacing.xs) {
                Text("משלמים ב-Apple Pay?")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isFocused)
                Text("אפשר להגדיר קיצור שיפתח את עכבר עו״ש מיד אחרי תשלום בארנק, עם הסכום ובית העסק כבר ממולאים. זה לוקח דקה, פעם אחת.")
                    .font(Theme.Typography.bodySmall)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: Theme.Spacing.sm) {
                Button {
                    onSetUp(dontShowAgain)
                } label: {
                    Text("איך מגדירים")
                        .font(Theme.Typography.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)

                Button {
                    onDismiss(dontShowAgain)
                } label: {
                    Text("לא עכשיו")
                        .font(Theme.Typography.body)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.accent)
            }

            Divider()

            Toggle("אל תראה לי שוב", isOn: $dontShowAgain)
                .font(Theme.Typography.bodySmall)
                .foregroundStyle(Theme.Colors.textSecondary)
                .tint(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: 380)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        // Behaves as a dialog for VoiceOver: nothing behind it is reachable
        // while it's up, and focus lands on its title.
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { onDismiss(dontShowAgain) }
        .onAppear { isFocused = true }
    }
}

/// When the tip may be offered. The permanent opt-out is the popup's toggle,
/// stored in `UserDefaults` (a per-device display preference, like the
/// dashboard's `acknowledgedOverrunMonth`); the per-launch flag keeps it to
/// once per launch however often the sheet is opened.
@MainActor
enum ApplePayTip {
    static let hiddenKey = "applePayTipHidden"
    static var shownThisLaunch = false
}

#Preview {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        ApplePayTipPopup(onSetUp: { _ in }, onDismiss: { _ in })
    }
    .environment(\.layoutDirection, .rightToLeft)
}
