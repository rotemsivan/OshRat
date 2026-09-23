import SwiftUI

/// The patch itself. Earned: struck in its tier's metal — a pale tint of it
/// behind a glyph and ring in the full colour. Not yet: a dashed outline with
/// the glyph ghosted, so the shelf shows what's there to collect.
///
/// Shared by the profile shelf, its detail popover and the achievement toast,
/// so a patch looks the same wherever it appears.
struct AchievementBadge: View {
    let achievement: Achievement
    let isUnlocked: Bool
    @ScaledMetric private var diameter: CGFloat

    init(achievement: Achievement, isUnlocked: Bool, diameter: CGFloat) {
        self.achievement = achievement
        self.isUnlocked = isUnlocked
        // Bare attribute, set here — see `ProfileAvatar` for why.
        _diameter = ScaledMetric(wrappedValue: diameter, relativeTo: .body)
    }

    private var metal: Color {
        switch achievement.tier {
        case .bronze: return Theme.Colors.tierBronze
        case .silver: return Theme.Colors.tierSilver
        case .gold:   return Theme.Colors.tierGold
        }
    }

    var body: some View {
        ZStack {
            if isUnlocked {
                Circle().fill(metal.opacity(0.15))
                Circle().strokeBorder(metal, lineWidth: 2)
            } else {
                Circle().strokeBorder(
                    Theme.Colors.separator,
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                )
            }

            Image(systemName: achievement.symbolName)
                // Sized off the scaled diameter, so the glyph grows with the
                // badge under Dynamic Type.
                .font(.system(size: diameter * 0.4, weight: .semibold))
                .foregroundStyle(isUnlocked ? metal : Theme.Colors.textSecondary.opacity(0.45))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
