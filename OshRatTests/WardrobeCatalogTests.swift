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
        #expect(WardrobeItem.unlocked(exactlyAt: 7).map(\.id) == [
            "item-hat-propeller-red", "item-glasses-aviator-gold", "item-glasses-aviator-silver",
        ])
        #expect(WardrobeItem.unlocked(exactlyAt: 19).isEmpty)
    }

    /// Ids name their slot (`item-<slot>-…`), which is also the asset folder
    /// the art lives in — a hat filed as an outfit would draw on the wrong
    /// layer.
    @Test func idsNameTheirSlot() {
        for item in WardrobeItem.catalogue {
            #expect(item.id.hasPrefix("item-\(item.slot.rawValue)-"), "\(item.id)")
        }
    }

    @Test func slotsHoldTheShippedArt() {
        #expect(WardrobeItem.items(in: .hat).count == 23)
        #expect(WardrobeItem.items(in: .glasses).count == 12)
        #expect(WardrobeItem.items(in: .outfit).count == 32)
        #expect(WardrobeItem.items(in: .prop).isEmpty)
        #expect(WardrobeItem.items(in: .background).isEmpty)
    }

    /// The first eight hats shipped at these levels. Moving one later would
    /// strip it off a rat already wearing it, so they're pinned.
    @Test func theOriginalHatsKeepTheirLevels() {
        let pinned = [
            "item-hat-cap-red": 2, "item-hat-cap-green": 3, "item-hat-cap-navy": 5,
            "item-hat-propeller-red": 7, "item-hat-propeller-green": 9,
            "item-hat-propeller-navy": 12, "item-hat-cap-gold": 15, "item-hat-propeller-gold": 20,
        ]
        for (id, level) in pinned {
            #expect(WardrobeItem.withID(id)?.unlockLevel == level, "\(id)")
        }
    }

    /// Every tab the wardrobe shows is a slot, and every slot has a tab.
    @Test func everySlotHasATab() {
        #expect(Set(WardrobeSlot.tabOrder) == Set(WardrobeSlot.allCases))
        #expect(WardrobeSlot.tabOrder.count == WardrobeSlot.allCases.count)
    }
}
