import Testing
@testable import OshRat

/// The wardrobe catalogue and its level-based unlocks. Ids are persisted in
/// `MascotConfig` and double as asset-name stems, so their shape is pinned.
struct WardrobeCatalogTests {

    @Test func idsAreUnique() {
        let ids = WardrobeItem.catalogue.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// Every item needs both canvases; the asset names follow the id.
    @Test func assetNamesFollowTheID() {
        let cap = WardrobeItem.withID("item-hat-cap-red")
        #expect(cap?.bustAssetName == "item-hat-cap-red-bust")
        #expect(cap?.fullBodyAssetName == "item-hat-cap-red-full")
    }

    @Test func anItemUnlocksAtItsLevelAndStaysUnlocked() {
        let navy = WardrobeItem.withID("item-hat-cap-navy")!
        #expect(!navy.isUnlocked(atLevel: navy.unlockLevel - 1))
        #expect(navy.isUnlocked(atLevel: navy.unlockLevel))
        #expect(navy.isUnlocked(atLevel: 99))
    }

    /// Level 2 comes with onboarding, so the first hat is a day-one reward.
    @Test func theFirstHatIsReachableOnDayOne() {
        #expect(WardrobeItem.catalogue.map(\.unlockLevel).min() == 2)
    }

    /// Everything must be reachable on the curve.
    @Test func everyUnlockIsWithinTheLevelCap() {
        for item in WardrobeItem.catalogue {
            #expect(item.unlockLevel >= 1 && item.unlockLevel <= XPRules.maxLevel)
        }
    }

    /// Rarer tiers never unlock before commoner ones — a gold hat at level 3
    /// would make "gold" meaningless.
    @Test func tiersClimbWithLevel() {
        let rank: [AchievementTier: Int] = [.bronze: 0, .silver: 1, .gold: 2]
        let sorted = WardrobeItem.catalogue.sorted { $0.unlockLevel < $1.unlockLevel }
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            #expect(rank[earlier.tier]! <= rank[later.tier]!)
        }
    }

    @Test func levelUpsAnnounceExactlyWhatTheyUnlock() {
        #expect(WardrobeItem.unlocked(exactlyAt: 7).map(\.id) == ["item-hat-propeller-red"])
        #expect(WardrobeItem.unlocked(exactlyAt: 6).isEmpty)
    }

    @Test func hatsAreAllInTheHatSlot() {
        #expect(WardrobeItem.items(in: .hat).count == 8)
        #expect(WardrobeItem.items(in: .outfit).isEmpty)
    }
}
