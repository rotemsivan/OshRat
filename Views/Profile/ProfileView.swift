import SwiftUI
import SwiftData

/// The profile tab — who the user is, and how far they've come.
///
/// In the order the questions get asked: *who am I* — a compact, card-less
/// header of picture, name and profession — then *how long have I been at
/// this* (joined date and streak), *what am I aiming at* (the free-text goal
/// onboarding collected), and *how am I doing* — the level card that used to
/// sit on the dashboard, now that the dashboard carries only `XPLevelBadge`
/// — and, last, the achievements shelf.
///
/// **Read-only on purpose.** The personal details are captured by onboarding
/// and belong to the (still unbuilt) Settings screen, which also owns the
/// preferred currency and the business-day toggle. Splitting "look at your
/// standing" from "change your details" is the same call that split
/// `DepositInfoSheet` off the account editor.
struct ProfileView: View {
    /// The namespace the wardrobe's zoom transition grows out of the
    /// profile picture in. `HomeView` owns the wardrobe, since the
    /// dashboard's greeting rat opens the same screen.
    let wardrobeTransition: Namespace.ID
    var onOpenWardrobe: () -> Void = {}

    @Query private var profiles: [UserProfile]
    /// Sorted oldest-first to match the row `ProgressService` resolves to —
    /// the same ordering `HomeView` uses, so the card here and the battery on
    /// the dashboard always read the same row.
    @Query(sort: \UserProgress.createdAt, order: .forward)
    private var progressRows: [UserProgress]

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                identityHeader
                statsCard

                // An empty goal is left out rather than shown as a blank
                // card: onboarding doesn't require one, and "your goal: —"
                // reads as a reproach in a finance app.
                if !goalsText.isEmpty {
                    goalCard
                }

                LevelProgressCard(progress: progressRows.first)

                AchievementsShelf(unlockedIDs: progressRows.first?.unlockedAchievements ?? [])
            }
            .padding(.horizontal, Theme.Spacing.lg)
            // A large navigation title brings its own vertical space, so the
            // content underneath keeps its top padding minimal.
            .padding(.top, Theme.Spacing.sm)
            // Bar clearance only, not the floating "+"'s: the last element is
            // a card with nothing tappable at its bottom edge, so letting the
            // "+" hover over it costs nothing and saves a screenful of dead
            // space at the end of the scroll.
            .padding(.bottom, HomeBottomBar.barClearance)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(Text("הפרופיל שלי"))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Identity

    /// Picture, name and profession as one compact row — no card behind it.
    ///
    /// Deliberately *not* `.cardStyle()`: a portrait centred in its own white
    /// panel, with the name in a second panel under it, cost most of the first
    /// screen before the stats even started. Sitting straight on the page and
    /// reading across, it costs about a fifth of that.
    ///
    /// The captions that used to label these ("שם", "מקצוע") are gone with the
    /// cards. They were what made the block tall, and a name beside a profile
    /// picture doesn't need telling apart from anything.
    ///
    /// `HStack` lays out from the right under RTL, so the picture leads and
    /// the text flows to its left — the same reading order as the dashboard's
    /// greeting mascot.
    private var identityHeader: some View {
        HStack(spacing: Theme.Spacing.md) {
            // The rat is the way into the wardrobe — tap yourself to dress.
            Button(action: onOpenWardrobe) {
                ProfileAvatar(wardrobeTransition: wardrobeTransition)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("המלתחה"))
            .accessibilityHint(Text("הלבשת העכבר שלך"))

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(verbatim: name.isEmpty ? String(localized: "ללא שם") : name)
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(
                        name.isEmpty ? Theme.Colors.textSecondary : Theme.Colors.textPrimary
                    )

                if !profession.isEmpty {
                    Text(verbatim: profession)
                        .font(Theme.Typography.bodySmall)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // `.contain`, not `.combine`: combining would fold the avatar button
        // into one element with the name and lose its action.
        .accessibilityElement(children: .contain)
    }

    // MARK: - Stats

    /// How long they've been at it, and how consistent they've been lately.
    ///
    /// This row is the streak's **permanent home**. `LevelProgressCard`
    /// further down shows the streak only until the first achievement is
    /// earned; after that its slot shows the latest achievement.
    private var statsCard: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            statTile(
                symbol: "calendar",
                label: Text("הצטרפת"),
                value: joinedText,
                tint: Theme.Colors.accent
            )

            Divider()
                .overlay(Theme.Colors.separator)
                // A `Divider` in an `HStack` has no height of its own; without
                // this it collapses to nothing between the two tiles.
                .frame(height: dividerHeight)

            statTile(
                symbol: "flame.fill",
                label: Text("רצף נוכחי"),
                value: streakText,
                // Lit only while there's a streak to show. Grey at zero is
                // the calm version of this — GAMIFICATION.md is explicit that
                // a gap is never punished, so no broken-flame icon either.
                tint: hasStreak ? Theme.Colors.wants : Theme.Colors.textSecondary
            )
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    @ScaledMetric(relativeTo: .body) private var dividerHeight: CGFloat = 52

    private func statTile(
        symbol: String,
        label: Text,
        value: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                label
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Text(verbatim: value)
                .font(Theme.Typography.amount)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Goal

    /// The free text from onboarding's "what are you aiming at?" step. Shown
    /// verbatim — `Text(verbatim:)` because this is the user's own sentence,
    /// not a Hebrew literal the string catalog should try to key on.
    private var goalCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label {
                Text("המטרה שלי")
                    .font(Theme.Typography.amount)
                    .foregroundStyle(Theme.Colors.textPrimary)
            } icon: {
                Image(systemName: "target")
                    .foregroundStyle(Theme.Colors.accent)
            }

            Text(verbatim: goalsText)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Data

    private var name: String { profiles.first?.name ?? "" }
    private var profession: String { profiles.first?.profession ?? "" }
    private var goalsText: String {
        (profiles.first?.goalsText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// When the profile row was written, which is the moment onboarding was
    /// finished — the app has no separate "joined" date and doesn't need one.
    /// Falls back to today so the tile never renders blank in the window
    /// between a wipe and the wizard taking over.
    private var joinedText: String {
        let joined = profiles.first?.createdAt ?? .now
        return joined.formatted(.dateTime.month(.abbreviated).year())
    }

    private var currentStreak: Int { progressRows.first?.currentStreak ?? 0 }

    private var hasStreak: Bool { currentStreak > 0 }

    /// `String(localized:)` so the count gets proper Hebrew plurals
    /// (יום / יומיים / N ימים) out of the catalog. At zero it's an invitation
    /// rather than a "0" — the same wording `LevelProgressCard` uses.
    private var streakText: String {
        guard hasStreak else { return String(localized: "מתחילים") }
        return String(localized: "\(currentStreak) ימים")
    }
}

// MARK: - Avatar

/// The profile picture: the user's own rat — dressed however they dressed it
/// in the wardrobe — framed in a circle.
///
/// The crop maths lives in `AvatarPortrait`, shared with the wardrobe's
/// tiles. It switches to the roomier framing when a hat is on, since a
/// propeller would otherwise lose its blades to the circle's edge.
private struct ProfileAvatar: View {
    // Bare attribute, with everything supplied in `init`: spelling the
    // arguments here *as well* leaves the wrapper wanting a `wrappedValue`
    // the caller can't give it.
    @ScaledMetric private var diameter: CGFloat

    /// The wardrobe zooms out of this picture and back into it.
    let wardrobeTransition: Namespace.ID

    @Query(sort: \MascotConfig.createdAt, order: .forward)
    private var configs: [MascotConfig]

    init(diameter: CGFloat = 68, wardrobeTransition: Namespace.ID) {
        _diameter = ScaledMetric(wrappedValue: diameter, relativeTo: .largeTitle)
        self.wardrobeTransition = wardrobeTransition
    }

    private var wearsHat: Bool { configs.first?.hatID != nil }

    var body: some View {
        AvatarPortrait(diameter: diameter, framing: wearsHat ? .headroom : .head) {
            UserAvatar(crop: .bust, pose: .thumbsup)
        }
        .background(Theme.Colors.accent.opacity(0.12))
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.Colors.separator, lineWidth: 1))
        // Zoom out of the round picture, not its square frame. The source
        // only accepts a `RoundedRectangle` clip, so it gets one with a
        // radius of exactly half the side — a circle. The radius has to be
        // exact: an oversized one isn't clamped here the way a plain shape's
        // is, and it clipped the whole picture away.
        .matchedTransitionSource(id: WardrobeEntryPoint.profilePicture, in: wardrobeTransition) { source in
            source.clipShape(RoundedRectangle(cornerRadius: diameter / 2))
        }
    }
}

#Preview {
    @Previewable @Namespace var wardrobeTransition
    NavigationStack {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ProfileView(wardrobeTransition: wardrobeTransition)
        }
    }
    .modelContainer(for: [UserProfile.self, UserProgress.self, MascotConfig.self], inMemory: true)
}
