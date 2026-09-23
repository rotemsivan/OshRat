import Foundation

/// Where an item sits on the avatar. Declared back to front, which is also
/// the order `UserAvatar` stacks the layers in (GAMIFICATION.md §7).
enum WardrobeSlot: String, CaseIterable, Identifiable {
    case background, outfit, hat, prop

    var id: String { rawValue }

    /// The wardrobe's tab label.
    var hebrewLabel: String {
        switch self {
        case .background: return "רקעים"
        case .outfit:     return "בגדים"
        case .hat:        return "כובעים"
        case .prop:       return "אביזרים"
        }
    }

    /// The order the wardrobe's tabs appear in — what a user reaches for
    /// first, not the drawing order.
    static let tabOrder: [WardrobeSlot] = [.hat, .outfit, .prop, .background]
}

/// One piece of the mascot's wardrobe.
///
/// The catalogue is **code, not data**, exactly like `Achievement` — only the
/// equipped choice per slot is persisted (`MascotConfig`), so adding or
/// rebalancing items is an edit, never a migration. Unlocks aren't stored at
/// all: they derive from the level, which never goes down, so an item can't
/// be taken away once earned.
///
/// Each item is two SVGs, one per canvas, named `<id>-bust` (400×520) and
/// `<id>-full` (360×660) in `Accessories/<Slot>/`. Drawn on the same canvases
/// as the Bare body, they register on every pose (see CLAUDE.md, Art assets).
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

    var bustAssetName: String { "\(id)-bust" }
    var fullBodyAssetName: String { "\(id)-full" }

    func isUnlocked(atLevel level: Int) -> Bool {
        level >= unlockLevel
    }
}

extension WardrobeItem {

    /// Every item, in the order the wardrobe shows them (by unlock level).
    ///
    /// The ladder front-loads the first hat (level 2 is reached during
    /// onboarding) and spaces the rest along the XP curve: level 5 is about a
    /// month of logging, 12 about four months, 20 about eleven.
    static let catalogue: [WardrobeItem] = [
        WardrobeItem(id: "item-hat-cap-red", name: "כובע מצחייה אדום", slot: .hat, tier: .bronze, unlockLevel: 2),
        WardrobeItem(id: "item-hat-cap-green", name: "כובע מצחייה ירוק", slot: .hat, tier: .bronze, unlockLevel: 3),
        WardrobeItem(id: "item-hat-cap-navy", name: "כובע מצחייה כחול", slot: .hat, tier: .bronze, unlockLevel: 5),
        WardrobeItem(id: "item-hat-propeller-red", name: "כובע פרופלור אדום", slot: .hat, tier: .silver, unlockLevel: 7),
        WardrobeItem(id: "item-hat-propeller-green", name: "כובע פרופלור ירוק", slot: .hat, tier: .silver, unlockLevel: 9),
        WardrobeItem(id: "item-hat-propeller-navy", name: "כובע פרופלור כחול", slot: .hat, tier: .silver, unlockLevel: 12),
        WardrobeItem(id: "item-hat-cap-gold", name: "כובע מצחייה זהב", slot: .hat, tier: .gold, unlockLevel: 15),
        WardrobeItem(id: "item-hat-propeller-gold", name: "כובע פרופלור זהב", slot: .hat, tier: .gold, unlockLevel: 20),
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
