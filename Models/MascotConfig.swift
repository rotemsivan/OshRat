import Foundation
import SwiftData

/// What the user's rat is wearing: one equipped item id per slot, `nil` for
/// "nothing" — which is how everyone starts, as the Bare rat.
///
/// Only the *choice* is stored. The items themselves are the code catalogue
/// (`WardrobeItem`), and what's unlocked derives from the level, so nothing
/// here can drift out of step with a rebalance (GAMIFICATION.md §4).
///
/// CloudKit rules as everywhere else: every property optional or defaulted,
/// no unique constraints. Like `UserProgress`, there's one row per user and
/// `WardrobeService.config(in:)` resolves to the oldest if two ever exist.
@Model
final class MascotConfig {
    var backgroundID: String?
    var outfitID: String?
    var hatID: String?
    var propID: String?

    var createdAt: Date = Date.now

    init() {
        self.createdAt = .now
    }

    func equippedID(for slot: WardrobeSlot) -> String? {
        switch slot {
        case .background: return backgroundID
        case .outfit:     return outfitID
        case .hat:        return hatID
        case .prop:       return propID
        }
    }

    func setEquippedID(_ id: String?, for slot: WardrobeSlot) {
        switch slot {
        case .background: backgroundID = id
        case .outfit:     outfitID = id
        case .hat:        hatID = id
        case .prop:       propID = id
        }
    }
}
