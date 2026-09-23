import SwiftUI

/// The profile's progress card: what level the user is on, how far into it
/// they are, and the most recent achievement they've earned (or, before the
/// first one, how many days in a row they've kept the ledger up to date).
///
/// Reads a `UserProgress` row and nothing else — all the arithmetic already
/// happened in `XPRules`. When there's no row yet (a user who has onboarded
/// but not logged anything) the card still draws, at level 1 with an empty
/// bar, because "you're at the start" is friendlier than a card that pops into
/// existence later for no visible reason.
///
/// Deliberately calm: no numbers racing upward, no badge to tap. Phase 1 of
/// GAMIFICATION.md is the engine and the feedback, not a game surface.
struct LevelProgressCard: View {
    let progress: UserProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                levelBadge
                Spacer(minLength: Theme.Spacing.sm)
                if let latestAchievement {
                    achievementPill(latestAchievement)
                } else {
                    streakPill
                }
            }

            ProgressView(value: levelProgress.fraction)
                .progressViewStyle(.linear)
                .tint(Theme.Colors.accent)

            HStack(spacing: Theme.Spacing.sm) {
                Text(nextLevelCaption)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer(minLength: Theme.Spacing.sm)
                lastAwardCaption
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .cardStyle()
        // One element for VoiceOver: read as a single status sentence rather
        // than four fragments, and the bar's own "47 percent" is replaced with
        // something that actually means something here.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("ההתקדמות שלי"))
        .accessibilityValue(Text(accessibilitySummary))
    }

    // MARK: - Pieces

    private var levelBadge: some View {
        // A capsule around live text, not a fixed-size circle: at the larger
        // Dynamic Type sizes a circle either clips the number or forces the
        // whole row taller than it needs to be.
        Text("רמה \(levelProgress.level)")
            .font(Theme.Typography.amount)
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.accent.opacity(0.12), in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// The most recently earned achievement: its patch in the tier's metal and
    /// its title. This is what the slot was reserved for (GAMIFICATION.md
    /// phase 2); the patch is the same `AchievementBadge` as on the shelf just
    /// below, so it reads as "the newest one of those".
    private func achievementPill(_ achievement: Achievement) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            AchievementBadge(achievement: achievement, isUnlocked: true, diameter: 24)
            Text(achievement.title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// Days in a row — shown in the achievement slot only until the first
    /// achievement exists, so a brand-new card isn't missing a corner. The
    /// streak's permanent home is the stats row on the profile tab.
    ///
    /// At zero it's an invitation rather than a scolding — GAMIFICATION.md is
    /// explicit that a gap is never punished or nagged about, so there's no
    /// "0 days" and no broken-flame icon.
    private var streakPill: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "flame.fill")
                .foregroundStyle(hasStreak ? Theme.Colors.wants : Theme.Colors.textSecondary)
            Text(streakText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// What the last points were for. One of the plan's guardrails is that the
    /// user can always see *why* XP arrived; with no XP ledger in phase 1,
    /// this line is that answer.
    @ViewBuilder
    private var lastAwardCaption: some View {
        if let progress, let reason = progress.lastAwardReason, progress.lastAwardXP > 0 {
            Text(lastAwardText(xp: progress.lastAwardXP, reason: reason))
                .font(Theme.Typography.captionSmall)
                .foregroundStyle(Theme.Colors.income)
                .lineLimit(1)
        }
    }

    // MARK: - Text

    /// "+5 תנועה נרשמה". Built as a `String` (so `Text` renders it verbatim
    /// rather than treating it as a catalog key) because the reason's label is
    /// already final Hebrew. The `+` is bidi-neutral and would drift to the
    /// wrong side of the number on an RTL line, so U+2066…U+2069 isolates it —
    /// the same trick the transaction lists use for signed amounts.
    private func lastAwardText(xp: Int, reason: XPReason) -> String {
        "\u{2066}+\(xp)\u{2069} \(reason.hebrewLabel)"
    }

    private var levelProgress: LevelProgress {
        progress?.levelProgress ?? XPRules.progress(forTotalXP: 0)
    }

    /// The last id in `unlockedAchievements` that this build's catalogue
    /// knows — the ledger is kept in the order achievements were earned.
    private var latestAchievement: Achievement? {
        progress?.unlockedAchievements.reversed().lazy.compactMap(Achievement.withID).first
    }

    private var currentStreak: Int { progress?.currentStreak ?? 0 }

    private var hasStreak: Bool { currentStreak > 0 }

    private var streakText: String {
        guard hasStreak else { return String(localized: "מתחילים רצף") }
        // `String(localized:)` so the count gets proper Hebrew plurals
        // (יום אחד / יומיים / N ימים) from the catalog.
        return String(localized: "\(currentStreak) ימים ברצף")
    }

    private var nextLevelCaption: String {
        guard !levelProgress.isMaxLevel else {
            return String(localized: "הגעת לרמה הגבוהה ביותר")
        }
        return String(
            localized: "עוד \(levelProgress.xpRemaining) נק׳ לרמה \(levelProgress.level + 1)"
        )
    }

    private var accessibilitySummary: String {
        var parts = [String(localized: "רמה \(levelProgress.level)"), nextLevelCaption]
        if let latestAchievement {
            parts.append(String(localized: "הישג אחרון: \(latestAchievement.title)"))
        } else if hasStreak {
            parts.append(streakText)
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Mid-level") {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        LevelProgressCard(progress: nil)
            .padding(Theme.Spacing.lg)
    }
}
