import SwiftUI
import SwiftData

/// The wardrobe: the user's rat, large, and everything it can wear.
///
/// A screen of its own, owned by `HomeView` and presented full-screen with a
/// zoom transition out of the rat that was tapped — the dashboard's greeting
/// or the profile picture — so the little rat appears to grow into this one.
/// A swipe down shrinks it back. A tap puts an item on immediately and
/// saves it: there's no "save" step, because the preview *is* the result and
/// a changed mind is one more tap.
///
/// Items unlock by level (`WardrobeItem.unlockLevel`). Locked ones are shown,
/// dimmed, with the level that opens them — a collection the user can see
/// the shape of is the point, as with the achievements shelf.
struct WardrobeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \MascotConfig.createdAt, order: .forward)
    private var configs: [MascotConfig]
    @Query(sort: \UserProgress.createdAt, order: .forward)
    private var progressRows: [UserProgress]

    @State private var slot: WardrobeSlot = .hat
    /// Bumped by a tap on the big rat to replay its wave.
    @State private var waveCount = 0

    private var level: Int { progressRows.first?.level ?? 1 }

    private static let previewHeight: CGFloat = 380
    /// Where the feet rest on the full-body canvas, as a fraction of its height.
    private static let feetY: CGFloat = 568 / 660

    /// Everything currently worn, one entry per slot.
    private var outfit: [String?] {
        WardrobeSlot.allCases.map(equippedID(for:))
    }

    private func equippedID(for slot: WardrobeSlot) -> String? {
        configs.first?.equippedID(for: slot)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    preview

                    slotTabs

                    slotContent
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle(Text("המלתחה"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סיום") { dismiss() }
                }
            }
        }
        // A light tap whenever something goes on or comes off, so the change
        // is felt as well as seen. Keyed to the whole outfit, not the current
        // tab's item — switching tabs would otherwise change the trigger and
        // tap for nothing.
        .sensoryFeedback(.impact(weight: .light), trigger: outfit)
    }

    // MARK: - Preview

    /// The rat, large, on a soft spotlight. Taps make it wave.
    private var preview: some View {
        Button {
            wave()
        } label: {
            idlingRat
                .frame(height: Self.previewHeight)
                // A soft floor shadow under the feet. Placed from the
                // canvas's own coordinates, not by eye: the feet rest at
                // y≈568 of 660, well above the canvas's bottom edge, so
                // aligning to the frame's bottom left the rat floating.
                .background(alignment: .top) {
                    Ellipse()
                        .fill(Theme.Colors.accent.opacity(0.08))
                        .frame(width: 150, height: 22)
                        .offset(y: Self.previewHeight * Self.feetY - 11)
                }
                // The canvas runs on well below the feet (they rest at 568 of
                // 660); take that empty band back out of the layout, keeping
                // just enough for the shadow, so the tabs sit under the rat.
                .padding(.bottom, -Self.previewHeight * (1 - Self.feetY) + Theme.Spacing.md)
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.sm)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("הקש כדי שהעכבר ינופף"))
    }

    /// One chip per slot, scrolling sideways. Seven slots don't fit a
    /// segmented control at phone width — the labels truncate, and at large
    /// text sizes they'd be unreadable — so this is the filter-chip look
    /// from the transactions list instead.
    private var slotTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(WardrobeSlot.tabOrder) { tab in
                    let isSelected = tab == slot
                    Button {
                        slot = tab
                    } label: {
                        Text(tab.hebrewLabel)
                            .font(Theme.Typography.bodySmall)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.sm + Theme.Spacing.xs)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                isSelected ? Theme.Colors.accent.opacity(0.12) : Theme.Colors.surface,
                                in: .capsule
                            )
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        // Bleed to the screen edges so chips scroll off them rather than
        // vanishing at the gutter, and put the gutter back as a margin.
        .padding(.horizontal, -Theme.Spacing.lg)
        .contentMargins(.horizontal, Theme.Spacing.lg, for: .scrollContent)
    }

    /// The rat, alive: a slow breath (a slight vertical stretch) and a gentle
    /// sway, looping. Both pivot on the feet, so it moves without sliding off
    /// its shadow. The two tracks share one 4.8 s period so the loop has no
    /// seam. Under Reduce Motion it stands still.
    @ViewBuilder
    private var idlingRat: some View {
        let rat = wavingRat
        if reduceMotion {
            rat
        } else {
            let feet = UnitPoint(x: 0.5, y: Self.feetY)
            KeyframeAnimator(initialValue: IdleMotion(), repeating: true) { motion in
                rat
                    .scaleEffect(x: 1, y: motion.breath, anchor: feet)
                    .rotationEffect(.degrees(motion.sway), anchor: feet)
            } keyframes: { _ in
                KeyframeTrack(\.breath) {
                    CubicKeyframe(1.012, duration: 1.2)
                    CubicKeyframe(1.0, duration: 1.2)
                    CubicKeyframe(1.012, duration: 1.2)
                    CubicKeyframe(1.0, duration: 1.2)
                }
                KeyframeTrack(\.sway) {
                    CubicKeyframe(1.2, duration: 1.2)
                    CubicKeyframe(0, duration: 1.2)
                    CubicKeyframe(-1.2, duration: 1.2)
                    CubicKeyframe(0, duration: 1.2)
                }
            }
        }
    }

    /// The rat's wave: the right arm swings up and waves about its
    /// shoulder while the left foot kicks out — every layer riding its limb,
    /// so a sleeve, a pant leg and a shoe move with it in any outfit.
    ///
    /// Under Reduce Motion the arm steps to the wave pose and back, with no
    /// swing and no kick.
    private var wavingRat: some View {
        KeyframeAnimator(initialValue: AvatarRig.rest, trigger: waveCount) { rig in
            UserAvatar(crop: .fullBody, rig: reduceMotion ? rig.steppedToWave : rig)
        } keyframes: { _ in
            KeyframeTrack(\.rightArm) {
                CubicKeyframe(-135, duration: 0.3)
                CubicKeyframe(-115, duration: 0.18)
                CubicKeyframe(-150, duration: 0.18)
                CubicKeyframe(-120, duration: 0.18)
                CubicKeyframe(-140, duration: 0.18)
                CubicKeyframe(-135, duration: 0.12)
                CubicKeyframe(0, duration: 0.35)
            }
            KeyframeTrack(\.leftLeg) {
                LinearKeyframe(0, duration: 0.15)
                CubicKeyframe(15, duration: 0.2)
                LinearKeyframe(15, duration: 0.8)
                CubicKeyframe(0, duration: 0.3)
            }
        }
    }

    private func wave() {
        waveCount += 1
    }

    // MARK: - Items

    @ViewBuilder
    private var slotContent: some View {
        let items = WardrobeItem.items(in: slot)
        if items.isEmpty {
            // The other slots are waiting on art — say so calmly rather than
            // hiding the tab, so the wardrobe reads as a place that grows.
            ContentUnavailableView {
                Label("בקרוב", systemImage: "hanger")
            } description: {
                Text("פריטים חדשים בדרך למלתחה")
            }
            .padding(.top, Theme.Spacing.lg)
        } else {
            // Three to a row, always: at phone width that makes each tile
            // about a third of the screen, big enough to read the item on
            // the rat — an adaptive grid packed five small ones in.
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Theme.Spacing.md, alignment: .top),
                    count: 3
                ),
                spacing: Theme.Spacing.md
            ) {
                // "Nothing" first: the way to take the current item off.
                WardrobeItemTile(
                    slot: slot,
                    item: nil,
                    level: level,
                    isEquipped: equippedID(for: slot) == nil
                ) {
                    WardrobeService.unequip(slot, in: modelContext)
                }

                ForEach(items) { item in
                    WardrobeItemTile(
                        slot: slot,
                        item: item,
                        level: level,
                        isEquipped: equippedID(for: slot) == item.id
                    ) {
                        // Tapping what's already on takes it off again.
                        if equippedID(for: slot) == item.id {
                            WardrobeService.unequip(slot, in: modelContext)
                        } else {
                            WardrobeService.equip(item, atLevel: level, in: modelContext)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    WardrobeView()
        .modelContainer(for: [UserProgress.self, MascotConfig.self], inMemory: true)
}

/// The wardrobe rat's idle loop, as the values `KeyframeAnimator` interpolates.
private struct IdleMotion {
    /// Vertical scale around the feet; 1 is at rest.
    var breath: CGFloat = 1
    /// Degrees around the feet.
    var sway: Double = 0
}
