import SwiftUI

/// Top-of-dashboard greeting. Compact, two-line: a small muted "good
/// morning/afternoon/evening/night" in Hebrew, with the user's name
/// underneath in a medium-prominence weight.
///
/// Kept deliberately *not* hero-sized — the most prominent number on
/// the dashboard is the total balance, not the greeting.
struct GreetingHeaderView: View {
    let name: String
    /// The namespace the wardrobe's zoom transition grows out of this rat in.
    let wardrobeTransition: Namespace.ID
    /// Tapping the rat opens the wardrobe.
    var onAvatarTap: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Bumped on each appearance to replay the wave.
    @State private var waveTrigger = 0

    var body: some View {
        // HStack auto-mirrors in RTL: in Hebrew the mascot ends up on
        // the right (where the eye lands first) and the greeting text
        // flows to its left.
        HStack(alignment: .center, spacing: Theme.Spacing.xxs) {
            // The user's own rat, waving — dressed however they dressed it
            // in the wardrobe, which this opens.
            Button(action: onAvatarTap) {
                wavingRat
                    .frame(width: 96, height: 126)
                    // The wardrobe zooms out of this rat and back into it.
                    .matchedTransitionSource(id: WardrobeEntryPoint.greeting, in: wardrobeTransition)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("המלתחה"))
            .accessibilityHint(Text("הלבשת העכבר שלך"))

            VStack(alignment: .leading) {
                Text("\(greetingText)\(name.isEmpty ? "" : ",")")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if !name.isEmpty {
                    Text(name)
                        .font(Theme.Typography.screenTitle)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Pull the row down past the parent VStack's `.lg` spacing so
        // the mascot visually *sits on* the AssetsSummaryCard — its
        // feet rest on the card's top edge with a few points of
        // overlap, instead of floating above it.
        .padding(.bottom, -(Theme.Spacing.lg + Theme.Spacing.sm))
        // Default sibling order in a VStack draws later children on
        // top; without this the card would cover the rat's feet at
        // the overlap. Lifting the greeting row's z-index makes the
        // mascot read as sitting *on* the card instead of behind it.
        .zIndex(1)
    }

    /// The rat at rest, giving a short wave each time the dashboard appears.
    ///
    /// The dashboard branch is rebuilt on every switch to the Home tab, so
    /// `onAppear` fires on each arrival and bumps the trigger. The arm is a
    /// rig part, so it really swings about the shoulder — sleeve and all —
    /// with a small tilt and hop of the whole rat for warmth. Under Reduce
    /// Motion the tilt and hop stay at zero and the arm steps to the wave
    /// pose and back.
    private var wavingRat: some View {
        KeyframeAnimator(initialValue: WaveMotion(), trigger: waveTrigger) { motion in
            let rig = AvatarRig(rightArm: motion.rightArm)
            UserAvatar(crop: .bust, rig: reduceMotion ? rig.steppedToWave : rig)
                .rotationEffect(.degrees(reduceMotion ? 0 : motion.tilt), anchor: .bottom)
                .offset(y: reduceMotion ? 0 : motion.hop)
        } keyframes: { _ in
            // Wait out the tab's fade, raise the arm, wave, lower it.
            KeyframeTrack(\.rightArm) {
                LinearKeyframe(0, duration: 0.3)
                CubicKeyframe(-135, duration: 0.25)
                CubicKeyframe(-115, duration: 0.2)
                CubicKeyframe(-150, duration: 0.2)
                CubicKeyframe(-120, duration: 0.2)
                CubicKeyframe(-135, duration: 0.15)
                CubicKeyframe(0, duration: 0.35)
            }
            // A little side-to-side while the arm is up, settling to rest.
            KeyframeTrack(\.tilt) {
                LinearKeyframe(0, duration: 0.3)
                CubicKeyframe(-2, duration: 0.25)
                CubicKeyframe(2, duration: 0.4)
                CubicKeyframe(-1, duration: 0.4)
                SpringKeyframe(0, duration: 0.4)
            }
            // A small lift as the arm goes up.
            KeyframeTrack(\.hop) {
                LinearKeyframe(0, duration: 0.3)
                SpringKeyframe(-4, duration: 0.15)
                SpringKeyframe(0, duration: 0.4, spring: .bouncy)
            }
        }
        .onAppear { waveTrigger += 1 }
    }

    /// Hebrew greetings keyed to a coarse part-of-day split. Returned as
    /// a `Text` (not a `String`) so the literal stays a localisation key
    /// when interpolated into the composite greeting above.
    private var greetingText: Text {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return Text("בוקר טוב")          // morning
        case 12..<17: return Text("צוהריים טובים")     // afternoon
        case 17..<21: return Text("ערב טוב")          // evening
        default:      return Text("לילה טוב")          // night (21–04)
        }
    }
}

#Preview {
    @Previewable @Namespace var wardrobeTransition
    GreetingHeaderView(name: "רותם", wardrobeTransition: wardrobeTransition)
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.background)
}

/// The greeting rat's wave, as the values `KeyframeAnimator` interpolates.
private struct WaveMotion {
    /// The right arm's angle about its shoulder, in degrees (see `AvatarRig`).
    var rightArm: Double = 0
    /// Degrees, around the bust's base.
    var tilt: Double = 0
    /// Points; negative lifts.
    var hop: CGFloat = 0
}
