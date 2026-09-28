import SwiftUI

/// One run of XP earned, as the shell noticed it: the total before and after.
///
/// Derived from `UserProgress.totalXP` changing rather than reported by
/// `ProgressService`, so every source of XP — a logged transaction, a balance
/// correction, an achievement, a deposit payout — shows up here without each
/// write point having to remember to announce itself.
struct XPGain: Equatable, Identifiable {
    /// Stable across `merging`, so a second award landing while the toast is
    /// up tops up the running toast instead of restarting it.
    let id = UUID()
    let fromXP: Int
    private(set) var toXP: Int

    init(fromXP: Int, toXP: Int) {
        self.fromXP = fromXP
        self.toXP = toXP
    }

    var amount: Int { toXP - fromXP }

    func merging(upTo total: Int) -> XPGain {
        var copy = self
        copy.toXP = max(toXP, total)
        return copy
    }
}

/// A small pill that slides in under the status bar after XP is earned: the
/// points counting up, and the level bar filling from where it was to where
/// it is now.
///
/// Deliberately smaller and quieter than `CelebrationToast` — this happens on
/// every logged transaction, so its sound is a short, quiet sweep under the
/// transaction's own chime, and it holds only briefly. When the gain crosses
/// a level the bar fills to the brim and the level-up toast takes over next.
struct XPGainToast: View {
    let gain: XPGain
    /// Called once the toast has animated out; the parent clears its state.
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isShowing = false
    /// Flips once the pill is in, driving the count-up and the bar fill — so
    /// the user sees them move rather than arriving already done.
    @State private var hasFilled = false

    @ScaledMetric(relativeTo: .caption) private var barWidth: CGFloat = 96

    /// Same beat as `CelebrationToast`: the XP is usually earned in a sheet
    /// that's still sliding away when this mounts.
    private static let entranceDelay: Duration = .seconds(0.4)
    private static let holdDuration: Duration = .seconds(1.8)
    private static let slideDuration: TimeInterval = 0.3

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityHidden(true)

            // Isolates keep the "+" on the visual left of the digits under
            // RTL, as the summary cards do for signed amounts.
            Text("\u{2066}+\(displayedAmount)\u{2069} נק׳")
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.accent)
                .contentTransition(.numericText(value: Double(displayedAmount)))
                .monospacedDigit()

            bar

            Text("רמה \(startProgress.level)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .lineLimit(1)
        // A second award merged into a running toast tops it up in place.
        .animation(.easeOut(duration: 0.5), value: gain.toXP)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.surface, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, Theme.Spacing.lg)
        .offset(y: reduceMotion || isShowing ? 0 : -100)
        .opacity(isShowing ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("קיבלת \(gain.amount) נקודות"))
        .task(id: gain.id) { await run() }
    }

    // MARK: - Bar

    /// The level bar as `XPLevelBadge` draws it: a rectangle charge clipped
    /// to a capsule, growing from the visual right under RTL.
    private var bar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.Colors.accent.opacity(0.15))
            Rectangle()
                .fill(Theme.Colors.accent)
                .frame(width: barWidth * (hasFilled ? endFraction : startProgress.fraction))
        }
        .frame(width: barWidth, height: 8)
        .clipShape(Capsule())
    }

    // MARK: - Data

    private var startProgress: LevelProgress {
        XPRules.progress(forTotalXP: gain.fromXP)
    }

    /// Where the bar ends. A gain that crossed a level fills it completely
    /// instead of wrapping round to a near-empty bar, which would read as
    /// having *lost* progress — the level-up toast right after says the rest.
    private var endFraction: Double {
        let end = XPRules.progress(forTotalXP: gain.toXP)
        return end.level > startProgress.level ? 1 : end.fraction
    }

    private var displayedAmount: Int {
        hasFilled ? gain.amount : 0
    }

    // MARK: - Lifecycle

    /// Wait, slide in, fill, hold, slide out. Cancellation-aware like
    /// `CelebrationToast`: if a sheet comes up mid-run the task is cancelled,
    /// the parent keeps the gain, and it plays again once the way is clear.
    private func run() async {
        isShowing = false
        hasFilled = false
        do {
            try await Task.sleep(for: Self.entranceDelay)
            withAnimation(.spring(response: Self.slideDuration, dampingFraction: 0.85)) {
                isShowing = true
            }
            // A beat after landing, so the fill is watched rather than missed.
            try await Task.sleep(for: .seconds(0.2))
            withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.8)) {
                hasFilled = true
            }
            // The sweep starts with the fill, so the rise is heard as the bar
            // climbing. Played here rather than on mount: a run cancelled
            // during the entrance delay (a sheet came up) stays silent.
            CelebrationFeedback.shared.play(.xpGained)
            AccessibilityNotification.Announcement(String(localized: "קיבלת \(gain.amount) נקודות")).post()
            try await Task.sleep(for: Self.holdDuration)
            withAnimation(.easeIn(duration: Self.slideDuration)) {
                isShowing = false
            }
            try await Task.sleep(for: .seconds(Self.slideDuration))
        } catch {
            return
        }
        onDismiss()
    }
}

#Preview {
    ZStack(alignment: .top) {
        Theme.Colors.background.ignoresSafeArea()
        XPGainToast(gain: XPGain(fromXP: 40, toXP: 55), onDismiss: {})
    }
    .environment(\.layoutDirection, .rightToLeft)
}
