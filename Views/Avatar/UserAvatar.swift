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

/// The Bare rat's poses. They differ only in one arm, which is why a hat
/// drawn once registers on every one of them.
enum AvatarPose {
    case base, wave, present, thumbsup, confident, cheer

    /// The body layer's asset. Not every pose exists on both canvases — the
    /// bust has no `confident`/`cheer`, the full body no `present` — so a
    /// missing one falls back to `base` rather than to a blank image.
    func bodyAssetName(for crop: AvatarCrop) -> String {
        switch crop {
        case .bust:
            switch self {
            case .wave:     return "bare-bust-wave"
            case .present:  return "bare-bust-present"
            case .thumbsup: return "bare-bust-thumbsup"
            case .base, .confident, .cheer: return "bare-bust-base"
            }
        case .fullBody:
            switch self {
            case .wave:      return "bare-fullbody-wave"
            case .thumbsup:  return "bare-fullbody-thumbsup"
            case .confident: return "bare-fullbody-confident"
            case .cheer:     return "bare-fullbody-cheer"
            case .base, .present: return "bare-fullbody-base"
            }
        }
    }
}

/// The avatar drawn from an explicit outfit — back to front: background,
/// Bare body, outfit, glasses, hat, prop. Glasses go under the hat so a
/// brim can overlap the frames, never the other way round.
///
/// Every layer is on the same canvas and scaled to fit the same frame, which
/// is all it takes for them to register. The wardrobe's tiles use this
/// directly to preview an item on the rat; everything else uses `UserAvatar`.
struct AvatarLayers: View {
    let crop: AvatarCrop
    let pose: AvatarPose
    /// Equipped item per slot. Ids with no catalogue entry are skipped.
    let equipped: [WardrobeSlot: String]

    var body: some View {
        ZStack {
            layer(for: .background)
            layer(named: bodyPose.bodyAssetName(for: crop))
            layer(for: .outfit)
            layer(for: .glasses)
            layer(for: .hat)
            layer(for: .prop)
        }
        .aspectRatio(crop.aspectRatio, contentMode: .fit)
    }

    /// The pose the body is actually drawn in. An outfit is drawn with both
    /// sleeves at rest (the art has one cut, fitted to `base`), so over a
    /// waving body the rat grows a third arm — the bare one still waving
    /// beside two sleeves. Dressed, it stands; the wave keeps its whole-body
    /// tilt where one is animated (the greeting), so it still reads as a
    /// hello. Hats and glasses don't touch the arms and keep every pose.
    private var bodyPose: AvatarPose {
        equipped[.outfit].flatMap(WardrobeItem.withID) == nil ? pose : .base
    }

    @ViewBuilder
    private func layer(for slot: WardrobeSlot) -> some View {
        if let id = equipped[slot], let item = WardrobeItem.withID(id) {
            layer(named: crop == .bust ? item.bustAssetName : item.fullBodyAssetName)
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
    var pose: AvatarPose = .base

    @Query(sort: \MascotConfig.createdAt, order: .forward)
    private var configs: [MascotConfig]
    @Query(sort: \UserProgress.createdAt, order: .forward)
    private var progressRows: [UserProgress]

    var body: some View {
        AvatarLayers(crop: crop, pose: pose, equipped: equipped)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabel))
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

    private var accessibilityLabel: String {
        let names = WardrobeSlot.allCases.compactMap { equipped[$0].flatMap(WardrobeItem.withID)?.name }
        guard !names.isEmpty else { return String(localized: "העכבר שלך") }
        return String(localized: "העכבר שלך, עם \(names.formatted(.list(type: .and)))")
    }
}
