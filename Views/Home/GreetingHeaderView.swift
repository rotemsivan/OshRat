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
    /// How far above the row's bottom the greeting text must stop to clear
    /// the level badge hovering over the card's top-left edge (`HomeView`
    /// measures the badge). Only applied at the accessibility sizes: there
    /// the text column outgrows the rat, reaches the row's bottom and ran
    /// under the badge; at ordinary sizes it's centred beside the rat and
    /// clears it on its own.
    var badgeClearance: CGFloat = 0
    /// How the rat feels (`MascotMood`) — its face, its pose, how it greets.
    var mood: MascotMood = .calm
    /// Why, in the speech bubble under the name; `nil` says nothing.
    var moodLine: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Bumped on each appearance to replay the wave.
    @State private var waveTrigger = 0
    /// Whether the mood's bubble is up right now — see `bubbleLoop`.
    @State private var isBubbleShowing = false

    /// The bubble's rhythm: up for long enough to read, then gone for a
    /// while so the greeting can be read too.
    private static let bubbleDelay: Duration = .seconds(0.8)
    private static let bubbleHold: Duration = .seconds(3.5)
    private static let bubbleGap: Duration = .seconds(30)

    var body: some View {
        // HStack auto-mirrors in RTL: in Hebrew the mascot ends up on
        // the right (where the eye lands first) and the greeting text
        // flows to its left.
        HStack(alignment: .center, spacing: Theme.Spacing.xxs) {
            // The user's own rat, waving — dressed however they dressed it
            // in the wardrobe, which this opens.
            Button(action: onAvatarTap) {
                greetingRat
                    .frame(width: 106, height: 139)
                    // The wardrobe zooms out of this rat and back into it.
                    .matchedTransitionSource(id: WardrobeEntryPoint.greeting, in: wardrobeTransition)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("המלתחה"))
            .accessibilityHint(Text("הלבשת העכבר שלך"))
            .accessibilityValue(Text(verbatim: moodLine ?? ""))

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
            // The mood's bubble floats over the greeting rather than taking a
            // line of its own — it comes and goes (`bubbleLoop`), and the
            // layout shouldn't jump each time it does.
            // Top-aligned, so it partly covers the greeting line and leaves
            // the name below it clear.
            .overlay(alignment: .topLeading) {
                if isBubbleShowing, let moodLine {
                    MoodBubble(text: moodLine)
                        .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
                        .allowsHitTesting(false)
                        // VoiceOver hears the line on the rat instead (its
                        // accessibility value), which doesn't vanish.
                        .accessibilityHidden(true)
                }
            }
            .task(id: moodLine) { await bubbleLoop() }
            .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? badgeClearance : 0)
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

    /// The rat as it greets: in its mood's face and pose, with a gesture to
    /// match each time the dashboard appears — a wave when calm, a bounce
    /// when happy, a sigh when worried or sad, a stamp when angry.
    ///
    /// The dashboard branch is rebuilt on every switch to the Home tab, so
    /// `onAppear` fires on each arrival and bumps the trigger. Under Reduce
    /// Motion the tilt and hop stay at zero; the calm wave steps its arm to
    /// the wave pose and back.
    @ViewBuilder
    private var greetingRat: some View {
        Group {
            switch mood {
            case .calm: wavingRat
            case .happy: bouncingRat
            case .worried, .sad: sighingRat
            case .angry: stampingRat
            }
        }
        .onAppear { waveTrigger += 1 }
    }

    /// The calm greeting: the right arm really swings about the shoulder,
    /// sleeve and all, with a small tilt and hop of the whole rat for warmth.
    private var wavingRat: some View {
        KeyframeAnimator(initialValue: WaveMotion(), trigger: waveTrigger) { motion in
            let rig = AvatarRig(rightArm: motion.rightArm)
            moved(UserAvatar(crop: .bust, rig: reduceMotion ? rig.steppedToWave : rig), by: motion)
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
    }

    /// Happy: arms up, two little hops.
    private var bouncingRat: some View {
        KeyframeAnimator(initialValue: WaveMotion(), trigger: waveTrigger) { motion in
            moved(UserAvatar(crop: .bust, rig: mood.rig, mood: mood), by: motion)
        } keyframes: { _ in
            KeyframeTrack(\.hop) {
                LinearKeyframe(0, duration: 0.3)
                SpringKeyframe(-8, duration: 0.18)
                SpringKeyframe(0, duration: 0.25, spring: .bouncy)
                SpringKeyframe(-6, duration: 0.18)
                SpringKeyframe(0, duration: 0.4, spring: .bouncy)
            }
            KeyframeTrack(\.tilt) {
                LinearKeyframe(0, duration: 0.3)
                CubicKeyframe(2, duration: 0.3)
                CubicKeyframe(-2, duration: 0.3)
                SpringKeyframe(0, duration: 0.4)
            }
        }
    }

    /// Worried or sad: a slow sink and a droop of the head, then back.
    private var sighingRat: some View {
        KeyframeAnimator(initialValue: WaveMotion(), trigger: waveTrigger) { motion in
            moved(UserAvatar(crop: .bust, rig: mood.rig, mood: mood), by: motion)
        } keyframes: { _ in
            KeyframeTrack(\.hop) {
                LinearKeyframe(0, duration: 0.3)
                CubicKeyframe(4, duration: 0.7)
                CubicKeyframe(0, duration: 0.9)
            }
            KeyframeTrack(\.tilt) {
                LinearKeyframe(0, duration: 0.3)
                CubicKeyframe(-3, duration: 0.7)
                CubicKeyframe(0, duration: 0.9)
            }
        }
    }

    /// Angry: a quick stamp — a short shake and a jolt.
    private var stampingRat: some View {
        KeyframeAnimator(initialValue: WaveMotion(), trigger: waveTrigger) { motion in
            moved(UserAvatar(crop: .bust, rig: mood.rig, mood: mood), by: motion)
        } keyframes: { _ in
            KeyframeTrack(\.tilt) {
                LinearKeyframe(0, duration: 0.3)
                LinearKeyframe(-3, duration: 0.07)
                LinearKeyframe(3, duration: 0.09)
                LinearKeyframe(-3, duration: 0.09)
                LinearKeyframe(3, duration: 0.09)
                SpringKeyframe(0, duration: 0.3)
            }
            KeyframeTrack(\.hop) {
                LinearKeyframe(0, duration: 0.3)
                LinearKeyframe(-3, duration: 0.1)
                SpringKeyframe(0, duration: 0.3)
            }
        }
    }

    /// The whole-body part of a gesture; Reduce Motion keeps the rat still.
    private func moved(_ rat: some View, by motion: WaveMotion) -> some View {
        rat
            .rotationEffect(.degrees(reduceMotion ? 0 : motion.tilt), anchor: .bottom)
            .offset(y: reduceMotion ? 0 : motion.hop)
    }

    /// Shows the bubble, holds it, fades it, and does it again every
    /// `bubbleGap` for as long as the dashboard is up. Restarts — showing at
    /// once — whenever the line changes, and ends when there's nothing to say
    /// or the dashboard goes away (the task is cancelled with the view).
    private func bubbleLoop() async {
        withAnimation(.easeOut(duration: 0.2)) { isBubbleShowing = false }
        guard moodLine != nil else { return }
        do {
            // Let the greeting gesture start before the rat "speaks".
            try await Task.sleep(for: Self.bubbleDelay)
            while true {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isBubbleShowing = true }
                try await Task.sleep(for: Self.bubbleHold)
                withAnimation(.easeInOut(duration: 0.5)) { isBubbleShowing = false }
                try await Task.sleep(for: Self.bubbleGap)
            }
        } catch {
            // Cancelled: the line changed or the dashboard went away.
        }
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

/// What the rat says about its mood — a small bubble over the greeting
/// line while it's up, its tail pointing back at the rat. The tail is a `Shape` drawn toward its
/// rect's minimum x and offset toward leading; under RTL both mirror, so it
/// points at the rat on the visual right.
private struct MoodBubble: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .leading) {
                BubbleTail()
                    .fill(Theme.Colors.surface)
                    .frame(width: 8, height: 12)
                    .offset(x: -7)
            }
            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The greeting rat's gesture, as the values `KeyframeAnimator` interpolates.
private struct WaveMotion {
    /// The right arm's angle about its shoulder, in degrees (see `AvatarRig`).
    var rightArm: Double = 0
    /// Degrees, around the bust's base.
    var tilt: Double = 0
    /// Points; negative lifts.
    var hop: CGFloat = 0
}
