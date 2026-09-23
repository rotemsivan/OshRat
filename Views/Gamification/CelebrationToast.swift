import SwiftUI

/// The app's one celebration surface: a level reached, a patch unlocked, or a
/// batch of patches unlocked at once.
///
/// Slides in under the status bar with its chime and haptic, holds for a beat,
/// and takes itself away. It animates in *and* out from its own state rather
/// than relying on a transition at the mount site, because the thing that
/// triggers it is a SwiftData write from somewhere else entirely (often a
/// sheet that's already dismissing), so there's no `withAnimation` block
/// around the change for a transition to hang off.
///
/// Short and calm by design — GAMIFICATION.md asks for celebrations that don't
/// interrupt. It never blocks the UI underneath except on its own small
/// footprint. A tap on an achievement takes the user to the shelf that patch
/// now sits on; a tap on a level-up that unlocked a wardrobe item opens the
/// wardrobe; any other level-up just dismisses early.
struct CelebrationToast: View {
    let celebration: Celebration
    /// Where a tap on an achievement leads — the profile tab's shelf.
    let onOpenAchievements: () -> Void
    /// Where a tap on a level-up that unlocked an item leads.
    let onOpenWardrobe: () -> Void
    /// Called once the toast has finished animating out. The parent pops the
    /// queue here — not when it appears — so an interrupted animation can't
    /// leave a celebration unannounced.
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isShowing = false
    /// Set by the first dismissal. A tap near the end of the hold and the
    /// hold running out would otherwise both call `onDismiss`, popping the
    /// *next* celebration off the queue unseen.
    @State private var isDismissing = false

    /// How long the toast holds once it's in. Long enough to read a short
    /// Hebrew sentence, short enough not to sit on the dashboard.
    private static let holdDuration: Duration = .seconds(2.6)
    private static let slideDuration: TimeInterval = 0.35
    /// A beat before sliding in. The toast usually mounts the moment a sheet
    /// starts to dismiss (`HomeView` holds it back while one is up), and
    /// arriving while the sheet is still sliding away splits the eye.
    private static let entranceDelay: Duration = .seconds(0.4)

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            leadingArt
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
                subtitle
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
        .onTapGesture { handleTap() }
        // Not tappable while it's invisible — during the entrance delay it's
        // mounted at the top of the screen with nothing to see.
        .allowsHitTesting(isShowing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(spokenText))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(tapHint))
        .task(id: celebration) {
            // A new celebration reuses this view when the previous one pops,
            // so reset the per-run state before playing it.
            isDismissing = false
            await run()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var leadingArt: some View {
        switch celebration {
        case .levelUp:
            mascot(.thumbsup)
        case .achievement(let id):
            if let achievement = Achievement.withID(id) {
                AchievementBadge(achievement: achievement, isUnlocked: true, diameter: 44)
            } else {
                mascot(.present)
            }
        case .achievementBatch:
            mascot(.present)
        }
    }

    /// The user's own rat, dressed as they dressed it.
    private func mascot(_ pose: AvatarPose) -> some View {
        UserAvatar(crop: .bust, pose: pose)
            .accessibilityHidden(true)
    }

    /// The item a level-up just unlocked, if any — the toast leads with it.
    private var unlockedItem: WardrobeItem? {
        guard case .levelUp(let level) = celebration else { return nil }
        return WardrobeItem.unlocked(exactlyAt: level).first
    }

    @ViewBuilder
    private var title: some View {
        switch celebration {
        case .levelUp(let level):
            Text("עלית לרמה \(level)")
        case .achievement(let id):
            Text("הישג חדש: \(Achievement.withID(id)?.title ?? "")")
        case .achievementBatch(let count):
            Text("פתחת \(count) הישגים חדשים")
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch celebration {
        case .levelUp:
            if let item = unlockedItem {
                Text("פריט חדש במלתחה: \(item.name)")
            } else {
                Text("ממשיכים ככה")
            }
        case .achievement(let id):
            Text(verbatim: Achievement.withID(id)?.rewardLine ?? "")
        case .achievementBatch:
            Text("הקש כדי לראות אותם")
        }
    }

    /// What VoiceOver announces as the toast arrives, and its label.
    private var spokenText: String {
        switch celebration {
        case .levelUp(let level):
            if let item = unlockedItem {
                return String(localized: "עלית לרמה \(level). פריט חדש במלתחה: \(item.name)")
            }
            return String(localized: "עלית לרמה \(level)")
        case .achievement(let id):
            let achievement = Achievement.withID(id)
            return String(localized: "הישג חדש: \(achievement?.title ?? ""), \(achievement?.rewardLine ?? "")")
        case .achievementBatch(let count):
            return String(localized: "פתחת \(count) הישגים חדשים")
        }
    }

    private var tapHint: String {
        switch celebration {
        case .achievement, .achievementBatch: return String(localized: "הקש למעבר להישגים")
        case .levelUp: return unlockedItem != nil ? String(localized: "הקש לפתיחת המלתחה") : String(localized: "הקש לסגירה")
        }
    }

    /// Gold patches get their own phrase; bronze, silver and the batch toast
    /// (which has no single tier) share the standard one.
    private var moment: CelebrationFeedback.Moment {
        switch celebration {
        case .levelUp:
            return .levelUp
        case .achievement(let id):
            return Achievement.withID(id)?.tier == .gold ? .goldAchievement : .achievement
        case .achievementBatch:
            return .achievement
        }
    }

    private var offset: CGFloat {
        if reduceMotion { return 0 }
        return isShowing ? 0 : -120
    }

    // MARK: - Lifecycle

    /// Wait, in (with the chime and haptic), hold, out, then tell the parent.
    /// Cancellation-aware: if the view goes away before or during the hold
    /// (a sheet came up, the user switched tabs), `Task.sleep` throws and the
    /// queue is left alone, so the celebration comes back rather than being
    /// silently eaten.
    private func run() async {
        do {
            try await Task.sleep(for: Self.entranceDelay)
        } catch {
            return
        }
        withAnimation(.spring(response: Self.slideDuration, dampingFraction: 0.8)) {
            isShowing = true
        }
        CelebrationFeedback.shared.play(moment)
        AccessibilityNotification.Announcement(spokenText).post()
        do {
            try await Task.sleep(for: Self.holdDuration)
        } catch {
            return
        }
        dismiss()
    }

    private func handleTap() {
        switch celebration {
        case .achievement, .achievementBatch:
            onOpenAchievements()
        case .levelUp:
            if unlockedItem != nil { onOpenWardrobe() }
        }
        dismiss()
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true
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

#Preview("Level up") {
    ZStack(alignment: .top) {
        Theme.Colors.background.ignoresSafeArea()
        CelebrationToast(celebration: .levelUp(4), onOpenAchievements: {}, onOpenWardrobe: {}, onDismiss: {})
    }
}

#Preview("Achievement") {
    ZStack(alignment: .top) {
        Theme.Colors.background.ignoresSafeArea()
        CelebrationToast(celebration: .achievement(id: "log-100"), onOpenAchievements: {}, onOpenWardrobe: {}, onDismiss: {})
    }
}

#Preview("Batch") {
    ZStack(alignment: .top) {
        Theme.Colors.background.ignoresSafeArea()
        CelebrationToast(celebration: .achievementBatch(count: 10), onOpenAchievements: {}, onOpenWardrobe: {}, onDismiss: {})
    }
}
