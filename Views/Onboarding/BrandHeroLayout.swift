import SwiftUI

/// The brand screen the app opens on: the mascot pops in, the app name and a
/// line under it rise in behind it, and the actions settle at the bottom.
///
/// Shared by the first-launch welcome (`WelcomeView`) and the login screen
/// (`LoginView`), which differ only in the line under the name and in their
/// buttons — so the two can't drift apart visually.
///
/// Choreography on appear: the mascot pops in first (see
/// `WelcomeMascotView`), then the title block and the actions fade-slide up
/// on staggered delays. Both are driven by the single `showsContent` flip, so
/// they can never drift out of sync.
struct BrandHeroLayout<Actions: View>: View {
    let subtitle: String
    @ViewBuilder let actions: Actions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One-shot entrance flag for the text + actions stagger.
    @State private var showsContent = false

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
                    actions
                }
                .opacity(showsContent ? 1 : 0)
                .offset(y: showsContent || reduceMotion ? 0 : 14)
                .animation(entranceAnimation.delay(0.5), value: showsContent)
            }
            .padding(Theme.Spacing.lg)
        }
        .onAppear { showsContent = true }
    }

    /// Reduce Motion keeps the timing but drops the slide, leaving an
    /// opacity-only fade (the `offset` above is already pinned to 0).
    private var entranceAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.4)
            : .spring(response: 0.5, dampingFraction: 0.8)
    }
}

#Preview {
    BrandHeroLayout(subtitle: "ניהול תקציב אישי, פשוט ופרטי.") {
        HeroPrimaryButton("לחשבון שלי", isPressed: .constant(false)) {}
    }
}
