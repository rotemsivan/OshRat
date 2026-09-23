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
    /// Tapping the big rat makes it wave for a moment.
    @State private var isWaving = false

    /// Compact on purpose: the rat is the star of this screen, and the
    /// items are a strip of choices under it.
    @ScaledMetric(relativeTo: .body) private var tileWidth: CGFloat = 68

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

                    Picker("סוג פריט", selection: $slot) {
                        ForEach(WardrobeSlot.tabOrder) { slot in
                            Text(slot.hebrewLabel).tag(slot)
                        }
                    }
                    .pickerStyle(.segmented)

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

    /// The rat, alive: a slow breath (a slight vertical stretch) and a gentle
    /// sway, looping. Both pivot on the feet, so it moves without sliding off
    /// its shadow. The two tracks share one 4.8 s period so the loop has no
    /// seam. Under Reduce Motion it stands still.
    @ViewBuilder
    private var idlingRat: some View {
        let rat = UserAvatar(crop: .fullBody, pose: isWaving ? .wave : .base)
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

    /// Wave, hold it a moment, then settle — chained through the first
    /// animation's completion, with the hold as the second one's delay.
    private func wave() {
        guard !isWaving else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)) {
            isWaving = true
        } completion: {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25).delay(0.8)) {
                isWaving = false
            }
        }
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
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: tileWidth), spacing: Theme.Spacing.sm, alignment: .top)],
                spacing: Theme.Spacing.sm
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
