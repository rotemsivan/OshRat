import SwiftUI

/// "You reached level 4" — the one celebration in phase 1.
///
/// Slides in under the status bar, holds for a beat, and takes itself away.
/// It animates in *and* out from its own state rather than relying on a
/// transition at the mount site, because the thing that triggers it is a
/// SwiftData write from somewhere else entirely (often a sheet that's already
/// dismissing), so there's no `withAnimation` block around the change for a
/// transition to hang off.
///
/// Short and calm by design — GAMIFICATION.md asks for celebrations that don't
/// interrupt. It never blocks the UI underneath except on its own small
/// footprint, where a tap dismisses it early.
struct LevelUpToast: View {
    let level: Int
    /// Called once the toast has finished animating out. The parent clears the
    /// pending flag here — not when it appears — so an interrupted animation
    /// can't leave a level-up unannounced.
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isShowing = false

    /// How long the toast holds once it's in. Long enough to read a short
    /// Hebrew sentence, short enough not to sit on the dashboard.
    private static let holdDuration: Duration = .seconds(2.6)
    private static let slideDuration: TimeInterval = 0.35

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image("rat-mascot-thumbsup")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("עלית לרמה \(level)")
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("ממשיכים ככה")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, Theme.Spacing.lg)
        // Reduce Motion keeps the fade but drops the travel, which is the part
        // that actually causes trouble.
        .offset(y: offset)
        .opacity(isShowing ? 1 : 0)
        .onTapGesture { dismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("עלית לרמה \(level)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("הקש לסגירה"))
        .task(id: level) {
            await run()
        }
    }

    private var offset: CGFloat {
        if reduceMotion { return 0 }
        return isShowing ? 0 : -120
    }

    /// In, hold, out, then tell the parent. Cancellation-aware: if the view
    /// goes away mid-hold (the user switched tabs), `Task.sleep` throws and we
    /// leave the pending flag alone so the celebration comes back rather than
    /// being silently eaten.
    private func run() async {
        withAnimation(.spring(response: Self.slideDuration, dampingFraction: 0.8)) {
            isShowing = true
        }
        do {
            try await Task.sleep(for: Self.holdDuration)
        } catch {
            return
        }
        dismiss()
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: Self.slideDuration)) {
            isShowing = false
        }
        // Let the exit animation play out before the parent unmounts us.
        Task {
            try? await Task.sleep(for: .seconds(Self.slideDuration))
            onDismiss()
        }
    }
}

#Preview {
    ZStack(alignment: .top) {
        Theme.Colors.background.ignoresSafeArea()
        LevelUpToast(level: 4, onDismiss: {})
    }
}
