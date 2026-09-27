import SwiftUI
import SwiftData

/// Which canvas the avatar is drawn on — the bust (400×520) for spot art, or
/// the full body (360×660) for the wardrobe.
enum AvatarCrop {
    case bust, fullBody

    /// Width ÷ height of the canvas, for callers sizing a frame.
    var aspectRatio: CGFloat {
        switch self {
        case .bust:     return 400 / 520
        case .fullBody: return 360 / 660
        }
    }
}

/// The avatar drawn from an explicit outfit, as a rig: the Bare rat cut into
/// parts, each limb a group turned about its joint with whatever it wears
/// drawn *inside* the group, so a sleeve, a pant leg or a shoe takes exactly
/// its limb's rotation. Back to front:
///
///     background
///     → left leg (leg, pant leg, shoe) → right leg        full body only
///     → body → pants' hips → top's torso
///     → left arm (arm, sleeve) → right arm
///     → head → glasses → hat → prop
///
/// The legs sit behind the body so the hips hide their tops at any angle;
/// glasses sit under the hat so a brim can overlap the frames.
///
/// Every layer is on the same canvas and scaled to fit the same frame, which
/// is all it takes for them to register. The wardrobe's tiles use this
/// directly to preview an item on the rat; everything else uses `UserAvatar`.
struct AvatarLayers: View {
    let crop: AvatarCrop
    let rig: AvatarRig
    /// Equipped item per slot. Ids with no catalogue entry are skipped.
    let equipped: [WardrobeSlot: String]

    init(crop: AvatarCrop, pose: AvatarPose = .base, equipped: [WardrobeSlot: String]) {
        self.init(crop: crop, rig: pose.rig, equipped: equipped)
    }

    init(crop: AvatarCrop, rig: AvatarRig, equipped: [WardrobeSlot: String]) {
        self.crop = crop
        self.rig = rig
        self.equipped = equipped
    }

    var body: some View {
        let items = equipped.compactMapValues(WardrobeItem.withID)
        ZStack {
            bodyLayer(.background, items)
            if crop == .fullBody {
                part("tail")
                leg(.left, items)
                leg(.right, items)
            }
            part("body")
            bodyLayer(.pants, items)
            bodyLayer(.outfit, items)
            arm(.left, items)
            arm(.right, items)
            part("head")
            bodyLayer(.glasses, items)
            bodyLayer(.hat, items)
            bodyLayer(.prop, items)
        }
        .aspectRatio(crop.aspectRatio, contentMode: .fit)
        // The pivots are canvas coordinates measured from the left, and the
        // art is never mirrored. Under the app's RTL layout a rotation's
        // anchor would be measured from the right instead, turning each arm
        // about the other shoulder. Nothing in here is text, so pin it.
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: - Limbs

    private func arm(_ side: LimbSide, _ items: [WardrobeSlot: WardrobeItem]) -> some View {
        ZStack {
            part("arm-\(side.rawValue)")
            limbLayer(.outfit, side, items)
        }
        .rotationEffect(rig.arm(side), anchor: crop.armPivot(side))
    }

    private func leg(_ side: LimbSide, _ items: [WardrobeSlot: WardrobeItem]) -> some View {
        ZStack {
            part("leg-\(side.rawValue)")
            limbLayer(.pants, side, items)
            limbLayer(.shoes, side, items)
        }
        .rotationEffect(rig.leg(side), anchor: crop.legPivot(side))
    }

    // MARK: - Layers

    private func part(_ name: String) -> some View {
        layer(named: "\(crop.rigPrefix)-\(name)")
    }

    @ViewBuilder
    private func bodyLayer(_ slot: WardrobeSlot, _ items: [WardrobeSlot: WardrobeItem]) -> some View {
        if let name = items[slot]?.bodyAssetName(on: crop.canvas) {
            layer(named: name)
        }
    }

    @ViewBuilder
    private func limbLayer(_ slot: WardrobeSlot, _ side: LimbSide, _ items: [WardrobeSlot: WardrobeItem]) -> some View {
        if let name = items[slot]?.limbAssetName(side, on: crop.canvas) {
            layer(named: name)
        }
    }

    private func layer(named name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
    }
}

/// The user's own rat, wearing whatever they picked in the wardrobe — the
/// one view every appearance of the mascot goes through (the greeting, the
/// profile picture, the celebration toasts, the wardrobe itself), so a change
/// in the wardrobe shows everywhere at once.
///
/// Reads the store itself rather than taking the outfit as a parameter, so a
/// call site can't forget to pass it along and show a stale rat.
struct UserAvatar: View {
    var crop: AvatarCrop = .bust
    var rig: AvatarRig = .rest

    @Query(sort: \MascotConfig.createdAt, order: .forward)
    private var configs: [MascotConfig]
    @Query(sort: \UserProgress.createdAt, order: .forward)
    private var progressRows: [UserProgress]

    init(crop: AvatarCrop = .bust, pose: AvatarPose = .base) {
        self.crop = crop
        self.rig = pose.rig
    }

    /// For a caller animating the limbs itself.
    init(crop: AvatarCrop = .bust, rig: AvatarRig) {
        self.crop = crop
        self.rig = rig
    }

    var body: some View {
        let equipped = equipped
        AvatarLayers(crop: crop, rig: rig, equipped: equipped)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabel(for: equipped)))
    }

    /// The config's picks, minus anything the current level no longer
    /// unlocks — which can only happen if the ladder is rebalanced upward,
    /// and then the rat quietly takes the item off rather than wearing
    /// something the wardrobe shows as locked.
    private var equipped: [WardrobeSlot: String] {
        guard let config = configs.first else { return [:] }
        let level = progressRows.first?.level ?? 1
        var result: [WardrobeSlot: String] = [:]
        for slot in WardrobeSlot.allCases {
            if let id = config.equippedID(for: slot),
               let item = WardrobeItem.withID(id),
               item.isUnlocked(atLevel: level) {
                result[slot] = id
            }
        }
        return result
    }

    /// Names only what this crop shows — a bust can't be wearing shoes.
    private func accessibilityLabel(for equipped: [WardrobeSlot: String]) -> String {
        let names = WardrobeSlot.allCases
            .filter { $0.isDrawn(on: crop.canvas) }
            .compactMap { equipped[$0].flatMap(WardrobeItem.withID)?.name }
        guard !names.isEmpty else { return String(localized: "העכבר שלך") }
        return String(localized: "העכבר שלך, עם \(names.formatted(.list(type: .and)))")
    }
}
