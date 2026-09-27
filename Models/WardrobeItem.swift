import Foundation

/// Where an item sits on the avatar, declared roughly back to front. Only
/// roughly: pants and shoes are split across the leg groups, which are drawn
/// *behind* the body, so the exact stacking lives in `AvatarLayers`.
enum WardrobeSlot: String, CaseIterable, Identifiable {
    case background, shoes, pants, outfit, glasses, hat, prop

    var id: String { rawValue }

    /// The wardrobe's tab label.
    var hebrewLabel: String {
        switch self {
        case .background: return "רקעים"
        case .shoes:      return "נעליים"
        case .pants:      return "מכנסיים"
        case .outfit:     return "חולצות"
        case .glasses:    return "משקפיים"
        case .hat:        return "כובעים"
        case .prop:       return "אביזרים"
        }
    }

    /// Whether the slot has anything to draw on `canvas`. The bust stops at
    /// the waist, so pants and shoes only exist on the full body.
    func isDrawn(on canvas: AvatarCanvas) -> Bool {
        switch self {
        case .pants, .shoes: return canvas == .full
        default:             return true
        }
    }

    /// The order the wardrobe's tabs appear in — what a user reaches for
    /// first, head to toe, not the drawing order. `prop` has no tab: the
    /// slot and its stored choice stay (the rig still draws one), but
    /// there's no art for it and an empty accessories tab only got in the way.
    static let tabOrder: [WardrobeSlot] = [.hat, .glasses, .outfit, .pants, .shoes, .background]
}

/// The two canvases every piece of art is cut for, named as the asset-name
/// suffix: the bust (400×520) and the full body (360×660).
enum AvatarCanvas: String {
    case bust, full
}

/// Which of a pair of limbs — the rat's own left and right as the art draws
/// them (its left is the canvas's left; the art is never mirrored, RTL or not).
enum LimbSide: String, CaseIterable {
    case left, right
}

/// One piece of the mascot's wardrobe.
///
/// The catalogue is **code, not data**, exactly like `Achievement` — only the
/// equipped choice per slot is persisted (`MascotConfig`), so adding or
/// rebalancing items is an edit, never a migration. Unlocks aren't stored at
/// all: they derive from the level, which never goes down, so an item can't
/// be taken away once earned.
///
/// The art lives in `Accessories/<Slot>/`, every layer on the full canvas it
/// belongs to so it registers with the rig without offsets. What a slot's
/// item is cut into:
/// - hats, glasses (and later props, backgrounds): one piece per canvas,
///   `<id>-bust` / `<id>-full`.
/// - tops (`outfit`): `<id>-torso-<canvas>` on the body, plus
///   `<id>-sleeve-left-<canvas>` / `-right-` that ride their arm's rotation.
///   Puffer vests have no sleeves.
/// - pants, full canvas only: `<id>-hips-full` on the body, plus
///   `<id>-leg-left-full` / `-right-` riding their leg. Skirts have no legs.
/// - shoes, full canvas only: `<id>-left-full` / `-right-`, riding their leg.
struct WardrobeItem: Identifiable, Hashable {
    /// Persisted in `MascotConfig` and used as the asset-name stem — **never
    /// rename**.
    let id: String
    /// Final Hebrew text.
    let name: String
    let slot: WardrobeSlot
    /// Rarity — shares the achievement metals so a gold hat and a gold patch
    /// read as the same kind of rare.
    let tier: AchievementTier
    /// The level that unlocks it.
    let unlockLevel: Int
    /// Whether a top has sleeves or pants have legs. False for the puffer
    /// vests and the skirts, whose arms and legs stay bare fur.
    var coversLimbs = true

    /// The layer that sits on the body — the whole item for hats and
    /// glasses, a top's torso, pants' hips. `nil` where the item has nothing
    /// to draw there: shoes are all limb, and nothing below the waist
    /// exists on the bust.
    func bodyAssetName(on canvas: AvatarCanvas) -> String? {
        guard slot.isDrawn(on: canvas) else { return nil }
        switch slot {
        case .outfit: return "\(id)-torso-\(canvas.rawValue)"
        case .pants:  return "\(id)-hips-\(canvas.rawValue)"
        case .shoes:  return nil
        case .background, .glasses, .hat, .prop: return "\(id)-\(canvas.rawValue)"
        }
    }

    /// The layer that rides one limb, drawn inside that limb's group so it
    /// takes exactly the limb's rotation: a sleeve on an arm, a pant leg or a
    /// shoe on a leg. `nil` for items with no limb layers.
    func limbAssetName(_ side: LimbSide, on canvas: AvatarCanvas) -> String? {
        guard slot.isDrawn(on: canvas) else { return nil }
        switch slot {
        case .outfit where coversLimbs: return "\(id)-sleeve-\(side.rawValue)-\(canvas.rawValue)"
        case .pants where coversLimbs:  return "\(id)-leg-\(side.rawValue)-\(canvas.rawValue)"
        case .shoes:                    return "\(id)-\(side.rawValue)-\(canvas.rawValue)"
        default:                        return nil
        }
    }

    func isUnlocked(atLevel level: Int) -> Bool {
        level >= unlockLevel
    }
}

extension WardrobeItem {

    /// Every item, in the order the wardrobe shows them (by unlock level).
    ///
    /// The ladder front-loads the first rewards (level 2 is reached during
    /// onboarding) and spaces the rest along the XP curve: level 5 is about a
    /// month of logging, 12 about four months, 20 about eleven. Rarity bands
    /// by level — bronze through 6, silver 7–14, gold from 15 — so a metal
    /// always means the same stretch of effort.
    ///
    /// A design unlocks **all its colours at once** rather than one colour a
    /// level: 90 items one at a time would run the ladder years past where
    /// anyone gets to, and "the hoodie" is the reward, not "the mustard one".
    /// The first eight hats predate that and keep their own levels.
    ///
    /// An item may move **earlier** but never later — later would take it off
    /// a rat already wearing it (see `UserAvatar.equipped`). That's how the
    /// propeller hats came down to bronze when the art pack called them
    /// common. The gold cap and gold propeller stay gold: a gold colourway is
    /// the rare version of a common design, as with the gold sneakers.
    ///
    /// Names are final Hebrew text; a geresh is U+05F3 (׳), not an apostrophe.
    static let catalogue: [WardrobeItem] = [
        // MARK: Bronze — levels 2–6
        WardrobeItem(id: "item-hat-cap-red", name: "כובע מצחייה אדום", slot: .hat, tier: .bronze, unlockLevel: 2),
        WardrobeItem(id: "item-outfit-tee-white", name: "חולצת טי לבנה", slot: .outfit, tier: .bronze, unlockLevel: 2),
        WardrobeItem(id: "item-outfit-tee-black", name: "חולצת טי שחורה", slot: .outfit, tier: .bronze, unlockLevel: 2),
        WardrobeItem(id: "item-outfit-tee-red", name: "חולצת טי אדומה", slot: .outfit, tier: .bronze, unlockLevel: 2),
        WardrobeItem(id: "item-outfit-tee-green", name: "חולצת טי ירוקה", slot: .outfit, tier: .bronze, unlockLevel: 2),
        WardrobeItem(id: "item-outfit-tee-navy", name: "חולצת טי כחולה", slot: .outfit, tier: .bronze, unlockLevel: 2),
        WardrobeItem(id: "item-pants-jeans-blue", name: "ג׳ינס כחול", slot: .pants, tier: .bronze, unlockLevel: 2),
        WardrobeItem(id: "item-pants-jeans-black", name: "ג׳ינס שחור", slot: .pants, tier: .bronze, unlockLevel: 2),

        WardrobeItem(id: "item-hat-cap-green", name: "כובע מצחייה ירוק", slot: .hat, tier: .bronze, unlockLevel: 3),
        WardrobeItem(id: "item-glasses-reading-black", name: "משקפי קריאה שחורים", slot: .glasses, tier: .bronze, unlockLevel: 3),
        WardrobeItem(id: "item-glasses-reading-gold", name: "משקפי קריאה זהב", slot: .glasses, tier: .bronze, unlockLevel: 3),
        WardrobeItem(id: "item-shoes-sneakers-white", name: "סניקרס לבנות", slot: .shoes, tier: .bronze, unlockLevel: 3),
        WardrobeItem(id: "item-shoes-sneakers-black", name: "סניקרס שחורות", slot: .shoes, tier: .bronze, unlockLevel: 3),
        WardrobeItem(id: "item-shoes-sneakers-red", name: "סניקרס אדומות", slot: .shoes, tier: .bronze, unlockLevel: 3),

        WardrobeItem(id: "item-hat-beanie-red", name: "כובע גרב אדום", slot: .hat, tier: .bronze, unlockLevel: 4),
        WardrobeItem(id: "item-hat-beanie-navy", name: "כובע גרב כחול", slot: .hat, tier: .bronze, unlockLevel: 4),
        WardrobeItem(id: "item-hat-beanie-mustard", name: "כובע גרב חרדל", slot: .hat, tier: .bronze, unlockLevel: 4),
        WardrobeItem(id: "item-hat-propeller-red", name: "כובע פרופלור אדום", slot: .hat, tier: .bronze, unlockLevel: 4),
        WardrobeItem(id: "item-pants-shorts-khaki", name: "מכנסיים קצרים חאקי", slot: .pants, tier: .bronze, unlockLevel: 4),
        WardrobeItem(id: "item-pants-shorts-red", name: "מכנסיים קצרים אדומים", slot: .pants, tier: .bronze, unlockLevel: 4),

        WardrobeItem(id: "item-hat-cap-navy", name: "כובע מצחייה כחול", slot: .hat, tier: .bronze, unlockLevel: 5),
        WardrobeItem(id: "item-hat-propeller-green", name: "כובע פרופלור ירוק", slot: .hat, tier: .bronze, unlockLevel: 5),
        WardrobeItem(id: "item-outfit-vtee-white", name: "חולצת וי לבנה", slot: .outfit, tier: .bronze, unlockLevel: 5),
        WardrobeItem(id: "item-outfit-vtee-pink", name: "חולצת וי ורודה", slot: .outfit, tier: .bronze, unlockLevel: 5),
        WardrobeItem(id: "item-outfit-vtee-lilac", name: "חולצת וי לילך", slot: .outfit, tier: .bronze, unlockLevel: 5),
        WardrobeItem(id: "item-pants-sweats-grey", name: "מכנסי טרנינג אפורים", slot: .pants, tier: .bronze, unlockLevel: 5),
        WardrobeItem(id: "item-pants-sweats-navy", name: "מכנסי טרנינג כחולים", slot: .pants, tier: .bronze, unlockLevel: 5),

        WardrobeItem(id: "item-hat-bucket-green", name: "כובע טמבל ירוק", slot: .hat, tier: .bronze, unlockLevel: 6),
        WardrobeItem(id: "item-hat-bucket-sand", name: "כובע טמבל בצבע חול", slot: .hat, tier: .bronze, unlockLevel: 6),
        WardrobeItem(id: "item-hat-propeller-navy", name: "כובע פרופלור כחול", slot: .hat, tier: .bronze, unlockLevel: 6),
        WardrobeItem(id: "item-outfit-hoodie-grey", name: "קפוצ׳ון אפור", slot: .outfit, tier: .bronze, unlockLevel: 6),
        WardrobeItem(id: "item-outfit-hoodie-navy", name: "קפוצ׳ון כחול", slot: .outfit, tier: .bronze, unlockLevel: 6),
        WardrobeItem(id: "item-outfit-hoodie-mustard", name: "קפוצ׳ון חרדל", slot: .outfit, tier: .bronze, unlockLevel: 6),
        WardrobeItem(id: "item-shoes-flats-beige", name: "בלרינות בז׳", slot: .shoes, tier: .bronze, unlockLevel: 6),
        WardrobeItem(id: "item-shoes-flats-pink", name: "בלרינות ורודות", slot: .shoes, tier: .bronze, unlockLevel: 6),

        // MARK: Silver — levels 7–14
        WardrobeItem(id: "item-glasses-aviator-gold", name: "משקפי טייסים זהב", slot: .glasses, tier: .silver, unlockLevel: 7),
        WardrobeItem(id: "item-glasses-aviator-silver", name: "משקפי טייסים כסף", slot: .glasses, tier: .silver, unlockLevel: 7),

        WardrobeItem(id: "item-hat-beret-black", name: "ברט שחור", slot: .hat, tier: .silver, unlockLevel: 8),
        WardrobeItem(id: "item-hat-beret-red", name: "ברט אדום", slot: .hat, tier: .silver, unlockLevel: 8),
        WardrobeItem(id: "item-outfit-denim-blue", name: "ז׳קט ג׳ינס כחול", slot: .outfit, tier: .silver, unlockLevel: 8),
        WardrobeItem(id: "item-outfit-denim-black", name: "ז׳קט ג׳ינס שחור", slot: .outfit, tier: .silver, unlockLevel: 8),
        WardrobeItem(id: "item-pants-trousers-beige", name: "מכנסיים מחויטים בז׳", slot: .pants, tier: .silver, unlockLevel: 8),
        WardrobeItem(id: "item-pants-trousers-charcoal", name: "מכנסיים מחויטים אפורים", slot: .pants, tier: .silver, unlockLevel: 8),

        WardrobeItem(id: "item-glasses-wayfarer-black", name: "משקפי שמש שחורים", slot: .glasses, tier: .silver, unlockLevel: 9),
        WardrobeItem(id: "item-glasses-wayfarer-tortoise", name: "משקפי שמש מנומרים", slot: .glasses, tier: .silver, unlockLevel: 9),
        WardrobeItem(id: "item-outfit-cardigan-beige", name: "קרדיגן בז׳", slot: .outfit, tier: .silver, unlockLevel: 9),
        WardrobeItem(id: "item-outfit-cardigan-lilac", name: "קרדיגן לילך", slot: .outfit, tier: .silver, unlockLevel: 9),
        WardrobeItem(id: "item-shoes-oxfords-black", name: "נעלי אוקספורד שחורות", slot: .shoes, tier: .silver, unlockLevel: 9),
        WardrobeItem(id: "item-shoes-oxfords-brown", name: "נעלי אוקספורד חומות", slot: .shoes, tier: .silver, unlockLevel: 9),

        WardrobeItem(id: "item-hat-fedora-charcoal", name: "פדורה אפורה", slot: .hat, tier: .silver, unlockLevel: 10),
        WardrobeItem(id: "item-hat-fedora-tan", name: "פדורה חומה", slot: .hat, tier: .silver, unlockLevel: 10),
        WardrobeItem(id: "item-outfit-bomber-black", name: "מעיל בומבר שחור", slot: .outfit, tier: .silver, unlockLevel: 10),
        WardrobeItem(id: "item-outfit-bomber-olive", name: "מעיל בומבר זית", slot: .outfit, tier: .silver, unlockLevel: 10),
        WardrobeItem(id: "item-pants-skirt-navy", name: "חצאית כחולה", slot: .pants, tier: .silver, unlockLevel: 10, coversLimbs: false),
        WardrobeItem(id: "item-pants-skirt-pink", name: "חצאית ורודה", slot: .pants, tier: .silver, unlockLevel: 10, coversLimbs: false),

        WardrobeItem(id: "item-glasses-cateye-red", name: "משקפי חתול אדומים", slot: .glasses, tier: .silver, unlockLevel: 11),
        WardrobeItem(id: "item-glasses-cateye-tortoise", name: "משקפי חתול מנומרים", slot: .glasses, tier: .silver, unlockLevel: 11),
        WardrobeItem(id: "item-outfit-puffer-red", name: "מעיל פוך אדום", slot: .outfit, tier: .silver, unlockLevel: 11, coversLimbs: false),
        WardrobeItem(id: "item-outfit-puffer-navy", name: "מעיל פוך כחול", slot: .outfit, tier: .silver, unlockLevel: 11, coversLimbs: false),
        WardrobeItem(id: "item-outfit-blazer-navy", name: "בלייזר כחול", slot: .outfit, tier: .silver, unlockLevel: 11),
        WardrobeItem(id: "item-outfit-blazer-charcoal", name: "בלייזר אפור", slot: .outfit, tier: .silver, unlockLevel: 11),
        WardrobeItem(id: "item-shoes-boots-black", name: "מגפונים שחורים", slot: .shoes, tier: .silver, unlockLevel: 11),
        WardrobeItem(id: "item-shoes-boots-brown", name: "מגפונים חומים", slot: .shoes, tier: .silver, unlockLevel: 11),

        WardrobeItem(id: "item-glasses-oversized-pink", name: "משקפיים גדולים ורודים", slot: .glasses, tier: .silver, unlockLevel: 12),
        WardrobeItem(id: "item-glasses-oversized-white", name: "משקפיים גדולים לבנים", slot: .glasses, tier: .silver, unlockLevel: 12),
        WardrobeItem(id: "item-outfit-blazerw-cream", name: "ז׳קט מחויט שמנת", slot: .outfit, tier: .silver, unlockLevel: 12),
        WardrobeItem(id: "item-outfit-blazerw-red", name: "ז׳קט מחויט אדום", slot: .outfit, tier: .silver, unlockLevel: 12),
        WardrobeItem(id: "item-shoes-heels-black", name: "נעלי עקב שחורות", slot: .shoes, tier: .silver, unlockLevel: 12),
        WardrobeItem(id: "item-shoes-heels-red", name: "נעלי עקב אדומות", slot: .shoes, tier: .silver, unlockLevel: 12),

        WardrobeItem(id: "item-hat-cowboy-brown", name: "כובע בוקרים חום", slot: .hat, tier: .silver, unlockLevel: 13),
        WardrobeItem(id: "item-hat-cowboy-sand", name: "כובע בוקרים בצבע חול", slot: .hat, tier: .silver, unlockLevel: 13),
        WardrobeItem(id: "item-outfit-waistcoat-brown", name: "וסט חום", slot: .outfit, tier: .silver, unlockLevel: 13),
        WardrobeItem(id: "item-outfit-waistcoat-charcoal", name: "וסט אפור", slot: .outfit, tier: .silver, unlockLevel: 13),
        WardrobeItem(id: "item-outfit-trench-beige", name: "מעיל טרנץ׳ בז׳", slot: .outfit, tier: .silver, unlockLevel: 13),
        WardrobeItem(id: "item-outfit-trench-black", name: "מעיל טרנץ׳ שחור", slot: .outfit, tier: .silver, unlockLevel: 13),

        WardrobeItem(id: "item-hat-graduation-black", name: "כובע בוגרים", slot: .hat, tier: .silver, unlockLevel: 14),
        WardrobeItem(id: "item-outfit-overcoat-camel", name: "מעיל צמר קאמל", slot: .outfit, tier: .silver, unlockLevel: 14),
        WardrobeItem(id: "item-outfit-overcoat-charcoal", name: "מעיל צמר אפור", slot: .outfit, tier: .silver, unlockLevel: 14),

        // MARK: Gold — level 15 on, where every level costs the same
        WardrobeItem(id: "item-hat-cap-gold", name: "כובע מצחייה זהב", slot: .hat, tier: .gold, unlockLevel: 15),
        WardrobeItem(id: "item-glasses-party-star", name: "משקפי כוכבים", slot: .glasses, tier: .gold, unlockLevel: 15),
        WardrobeItem(id: "item-hat-tophat-black", name: "צילינדר", slot: .hat, tier: .gold, unlockLevel: 16),
        WardrobeItem(id: "item-outfit-tuxedo-black", name: "טוקסידו", slot: .outfit, tier: .gold, unlockLevel: 17),
        WardrobeItem(id: "item-pants-tuxedo-black", name: "מכנסי טוקסידו", slot: .pants, tier: .gold, unlockLevel: 17),
        WardrobeItem(id: "item-glasses-party-heart", name: "משקפי לבבות", slot: .glasses, tier: .gold, unlockLevel: 18),
        WardrobeItem(id: "item-hat-propeller-gold", name: "כובע פרופלור זהב", slot: .hat, tier: .gold, unlockLevel: 20),
        WardrobeItem(id: "item-hat-crown-gold", name: "כתר זהב", slot: .hat, tier: .gold, unlockLevel: 23),
        WardrobeItem(id: "item-shoes-sneakers-gold", name: "סניקרס זהב", slot: .shoes, tier: .gold, unlockLevel: 22),
        // The capstone: together these dress the rat as the Classic mascot
        // from the onboarding screen — the user earns the brand.
        WardrobeItem(id: "item-outfit-suit-classic", name: "החליפה הקלאסית", slot: .outfit, tier: .gold, unlockLevel: 25),
        WardrobeItem(id: "item-hat-classic-navy", name: "הכובע הקלאסי", slot: .hat, tier: .gold, unlockLevel: 25),
        WardrobeItem(id: "item-pants-suit-classic", name: "מכנסי החליפה הקלאסית", slot: .pants, tier: .gold, unlockLevel: 25),
    ]

    static func withID(_ id: String) -> WardrobeItem? {
        catalogue.first { $0.id == id }
    }

    static func items(in slot: WardrobeSlot) -> [WardrobeItem] {
        catalogue.filter { $0.slot == slot }
    }

    /// What reaching exactly `level` unlocks — what the level-up toast
    /// announces.
    static func unlocked(exactlyAt level: Int) -> [WardrobeItem] {
        catalogue.filter { $0.unlockLevel == level }
    }
}
