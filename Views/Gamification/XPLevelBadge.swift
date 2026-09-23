import SwiftUI

/// The dashboard's XP readout: a capsule that fills left-to-right (right-to-
/// left, here) with progress through the current level, with the level itself
/// written inside it.
///
/// Rests on the assets card's top edge without cutting into it, mirroring the
/// greeting mascot on the opposite corner. Deliberately a *status light*, not
/// a control — it says
/// where you are; the profile tab says what it took to get there and what's
/// next. (Tapping it does nothing: the rat in the bottom bar is the one way
/// into the profile, so there's a single answer to "where do I go for this?")
///
/// Reads the same `LevelProgress` `LevelProgressCard` does, so the two can
/// never disagree about what level the user is on.
struct XPLevelBadge: View {
    let progress: UserProgress?

    /// A floor, not a fixed width — the capsule still grows with the text at
    /// larger Dynamic Type sizes. Without it, "רמה 5" hugs so tightly that
    /// the filled portion has no room to read as a proportion of anything.
    @ScaledMetric(relativeTo: .caption) private var minimumWidth: CGFloat = 92

    var body: some View {
        Text("רמה \(levelProgress.level)")
            .font(Theme.Typography.caption)
            // Primary, not the accent: this text sits over the fill on one
            // side and the empty track on the other, and it has to stay
            // legible across that boundary. A near-black reads at better than
            // 7:1 on both, in either colour scheme; accent-on-accent-tint
            // would not.
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(minWidth: minimumWidth)
            .background { capsuleFill }
            .overlay(Capsule().stroke(Theme.Colors.accent.opacity(0.25), lineWidth: 1))
            // It sits flush on the card's top edge, so the shadow falls onto
            // the card itself — which is exactly what makes it read as resting
            // *on* the card rather than as a tab glued to its side.
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("רמה \(levelProgress.level)"))
            .accessibilityValue(Text(accessibilityValue))
    }

    // MARK: - Fill

    /// Opaque base, then the track tint, then the charge.
    ///
    /// The base is opaque so the badge reads as a solid chip against the page
    /// rather than a tinted patch of it — the two tints above it are meant to
    /// be a fill level, not a transparency.
    private var capsuleFill: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Theme.Colors.surface
                Theme.Colors.accent.opacity(0.12)

                // A plain `Rectangle` clipped to the capsule, *not* a second
                // `Capsule`: a capsule fill rounds its growing edge too, and
                // a rounded pill inside a rounded pill reads as a toggle
                // switch rather than a level that's part-way full.
                //
                // `.leading` mirrors under RTL, so it grows from the visual
                // right — the direction a Hebrew reader expects.
                Rectangle()
                    .fill(Theme.Colors.accent.opacity(0.35))
                    .frame(width: geometry.size.width * levelProgress.fraction)
            }
            .clipShape(Capsule())
        }
        // A fresh user sits at exactly zero, and an empty capsule beside
        // "רמה 1" is the honest picture — the streak card is where the app
        // does encouragement, not here.
        .animation(.easeOut(duration: 0.3), value: levelProgress.fraction)
    }

    // MARK: - Data

    private var levelProgress: LevelProgress {
        progress?.levelProgress ?? XPRules.progress(forTotalXP: 0)
    }

    private var accessibilityValue: String {
        guard !levelProgress.isMaxLevel else {
            return String(localized: "הגעת לרמה הגבוהה ביותר")
        }
        return String(
            localized: "עוד \(levelProgress.xpRemaining) נק׳ לרמה \(levelProgress.level + 1)"
        )
    }
}

#Preview("Empty") {
    ZStack {
        Theme.Colors.background.ignoresSafeArea()
        XPLevelBadge(progress: nil)
    }
}
