import SwiftUI
import SwiftData

/// The profile tab — who the user is, and how far they've come.
///
/// In the order the questions get asked: *who am I* — a compact, card-less
/// header of picture, name and profession — then *how long have I been at
/// this* (joined date and streak), *what am I aiming at* (the free-text goal
/// onboarding collected), and *how am I doing* — the level card that used to
/// sit on the dashboard, now that the dashboard carries only `XPLevelBadge`.
///
/// **Read-only on purpose.** The personal details are captured by onboarding
/// and belong to the (still unbuilt) Settings screen, which also owns the
/// preferred currency and the business-day toggle. Splitting "look at your
/// standing" from "change your details" is the same call that split
/// `DepositInfoSheet` off the account editor.
struct ProfileView: View {
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

                AchievementsGalleryPlaceholder()
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
            ProfileAvatar()

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
        .accessibilityElement(children: .combine)
    }

    // MARK: - Stats

    /// How long they've been at it, and how consistent they've been lately.
    ///
    /// This row is the streak's **permanent home**. It also shows on
    /// `LevelProgressCard` further down, but only as a stand-in: that slot
    /// goes to the most recent achievement in GAMIFICATION.md phase 2. So the
    /// overlap is temporary by design — don't resolve it by deleting this tile.
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

/// The profile picture: the mascot's head, framed in a circle.
///
/// The bust art is a 400×520 portrait, so dropping it into a circle needs the
/// crop worked out rather than a plain `.scaledToFill()`, which would slice
/// the ears off: in `rat-mascot-thumbsup` the head sits at (200, 160) — centred
/// horizontally, but only ~31% down — and the ears span 45% of the width. The
/// two constants below do that framing, and hold at any diameter.
///
/// Phase 3 of GAMIFICATION.md replaces this single `Image` with the layered
/// wardrobe render; the framing maths is what stays, since every layer is
/// drawn against the same canvas. `diameter` is a parameter for the same
/// reason — the wardrobe screen wants this same view rendered large.
private struct ProfileAvatar: View {
    // Bare attribute, with everything supplied in `init`: spelling the
    // arguments here *as well* leaves the wrapper wanting a `wrappedValue`
    // the caller can't give it.
    @ScaledMetric private var diameter: CGFloat

    init(diameter: CGFloat = 68) {
        _diameter = ScaledMetric(wrappedValue: diameter, relativeTo: .largeTitle)
    }

    /// The bust art's own proportions, so the frame below can be stated in
    /// one dimension and stay true to the drawing.
    private static let artAspect: CGFloat = 520 / 400

    /// How much wider than the circle to draw the art. The vertical nudge is
    /// derived from it: the head centres on y 160 of 520, so dropping the art
    /// by `0.25 × zoom` lands the head on the circle's centre at any zoom.
    ///
    /// The ceiling comes from the ears. They sit at (152, 108) and (248, 108)
    /// with r 42, which puts each ear's far edge `0.282 × zoom` diameters
    /// from the head's centre — and, being *above* that centre, they have to
    /// clear the circle's width at their own height, not its full radius.
    /// That caps the zoom at ~1.77; 2.15 sheared both ears clean off.
    ///
    /// The thumbs-up hand (x 254–320, y 240–346) would need ~2.07 to fall
    /// outside the circle, so the two can't both be had with this pose: a
    /// sliver of knuckle at the lower edge is the price of whole ears. Worth
    /// revisiting if the wardrobe work in GAMIFICATION.md phase 3 brings an
    /// arms-down pose — none of the five Classic busts has one.
    private static let zoom: CGFloat = 1.75

    var body: some View {
        Circle()
            .fill(Theme.Colors.accent.opacity(0.12))
            .frame(width: diameter, height: diameter)
            .overlay {
                Image("rat-mascot-thumbsup")
                    .resizable()
                    // **Both** dimensions, deliberately. With only a width,
                    // the height proposal falls through from the circle, and
                    // `scaledToFit` then fits a portrait image to *that* —
                    // the picture comes out the circle's height and a third
                    // of the intended width, which is a very small rat.
                    .frame(
                        width: diameter * Self.zoom,
                        height: diameter * Self.zoom * Self.artAspect
                    )
                    .offset(y: diameter * 0.25 * Self.zoom)
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(Theme.Colors.separator, lineWidth: 1))
            .accessibilityLabel(Text("עכבר עו״ש"))
    }
}

// MARK: - Achievements

/// Phase 2 of GAMIFICATION.md in outline: the shelf the patches will sit on.
///
/// Drawn as empty, dashed slots rather than hidden until it's built. The plan
/// wants unlocks to feel like a collection, and a collection the user can see
/// the shape of is the point — but each slot is deliberately blank, because
/// showing named-but-locked achievements before the catalog exists would be
/// promising specific things the code can't yet award.
private struct AchievementsGalleryPlaceholder: View {
    /// Enough to read as a row with more to come, few enough to still fit at
    /// accessibility text sizes once the slots scale up.
    private let slotCount = 4

    @ScaledMetric(relativeTo: .body) private var slotSize: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
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

                Text("בקרוב")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.accent.opacity(0.12), in: Capsule())
            }

            // Wraps instead of scrolling: at the largest text sizes four
            // 56pt-based slots no longer fit one line, and a row that
            // silently runs off the card edge is worse than a second row.
            ViewThatFits(in: .horizontal) {
                slots
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) { slots }
            }

            Text("תגים על יעדים שתשלים — רצפים, חיסכון ועמידה בתקציב.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("הישגים"))
        .accessibilityValue(Text("בקרוב"))
    }

    private var slots: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(0..<slotCount, id: \.self) { _ in
                Circle()
                    .strokeBorder(
                        Theme.Colors.separator,
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                    )
                    .frame(width: slotSize, height: slotSize)
                    .overlay {
                        Image(systemName: "lock.fill")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary.opacity(0.5))
                    }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            ProfileView()
        }
    }
    .modelContainer(for: [UserProfile.self, UserProgress.self], inMemory: true)
}
