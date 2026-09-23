import SwiftUI

/// The achievements shelf on the profile tab — every patch in the catalogue,
/// earned or not, grouped by theme.
///
/// Locked patches are shown **named**, dimmed, with their icon. The old
/// placeholder kept its slots blank because naming achievements the code
/// couldn't award would have been a promise; now every reachable one *can* be
/// awarded, and a collection the user can see the shape of is the point.
/// The two goal patches, which can't be earned until the Goals UI exists,
/// say so rather than pretending to be ordinary locked ones.
///
/// Order is the catalogue's, not earned-first: the shelf is a collection, and
/// patches shuffling position as they unlock would make it read like a list.
struct AchievementsShelf: View {
    /// `UserProgress.unlockedAchievements`, passed in rather than queried so
    /// the shelf reads the same row the level card beside it does.
    let unlockedIDs: [String]

    /// The narrowest a patch column may get. Scaled so the grid drops to
    /// fewer, wider columns at large text sizes instead of squeezing titles.
    @ScaledMetric(relativeTo: .caption) private var minimumTileWidth: CGFloat = 76

    private var unlocked: Set<String> { Set(unlockedIDs) }

    private var earnedCount: Int {
        Achievement.catalogue.filter { unlocked.contains($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            ForEach(AchievementGroup.allCases, id: \.self) { group in
                section(for: group)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Label {
                Text("הישגים")
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
            } icon: {
                Image(systemName: "rosette")
                    .foregroundStyle(Theme.Colors.accent)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text("\(earnedCount) מתוך \(Achievement.catalogue.count)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Colors.accent.opacity(0.12), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }

    private func section(for group: AchievementGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(group.hebrewLabel)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityAddTraits(.isHeader)

            // Adaptive columns wrap on their own at any width or text size —
            // the placeholder's `ViewThatFits` offered two candidates of the
            // same width and so never wrapped (ACHIEVEMENTS.md §10).
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: minimumTileWidth), spacing: Theme.Spacing.sm, alignment: .top)],
                alignment: .leading,
                spacing: Theme.Spacing.md
            ) {
                ForEach(Achievement.catalogue.filter { $0.group == group }) { achievement in
                    AchievementPatch(achievement: achievement, isUnlocked: unlocked.contains(achievement.id))
                }
            }
        }
    }
}

// MARK: - Patch

/// One patch: the badge and its name, opening a small card with how to earn
/// it. Owns its own popover flag so the popover anchors to the patch that was
/// tapped, not to the shelf.
private struct AchievementPatch: View {
    let achievement: Achievement
    let isUnlocked: Bool

    @State private var isShowingDetail = false

    var body: some View {
        Button {
            isShowingDetail = true
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                AchievementBadge(achievement: achievement, isUnlocked: isUnlocked, diameter: 56)

                Text(achievement.title)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(isUnlocked ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(achievement.title))
        .accessibilityValue(Text(statusText))
        .accessibilityHint(Text(achievement.hint))
        .popover(isPresented: $isShowingDetail) {
            AchievementDetail(achievement: achievement, isUnlocked: isUnlocked)
                // A small card beside the patch on iPhone too, rather than a
                // sheet — it's three lines of text.
                .presentationCompactAdaptation(.popover)
        }
    }

    private var statusText: String {
        if isUnlocked { return "הושג, דרגת \(achievement.tier.hebrewLabel)" }
        return achievement.isReachable ? "טרם הושג" : "יהיה זמין בקרוב"
    }
}

// MARK: - Detail

/// What the popover shows: the patch, its tier and XP, where the user stands,
/// and how it's earned.
private struct AchievementDetail: View {
    let achievement: Achievement
    let isUnlocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                AchievementBadge(achievement: achievement, isUnlocked: isUnlocked, diameter: 40)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(achievement.title)
                        .font(Theme.Typography.amount)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(verbatim: achievement.rewardLine)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Text(achievement.hint)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            status
        }
        .padding(Theme.Spacing.md)
        .frame(width: 280, alignment: .leading)
    }

    @ViewBuilder
    private var status: some View {
        if isUnlocked {
            Label("הושג", systemImage: "checkmark.circle.fill")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.income)
        } else if !achievement.isReachable {
            Label("יהיה זמין עם מסך היעדים", systemImage: "clock")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

#Preview {
    ScrollView {
        AchievementsShelf(unlockedIDs: ["streak-7", "log-100", "first-deposit", "surplus-12"])
            .padding(Theme.Spacing.lg)
    }
    .background(Theme.Colors.background)
}
