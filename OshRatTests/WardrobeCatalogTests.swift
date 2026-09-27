import Testing
@testable import OshRat

/// The wardrobe catalogue and its level-based unlocks. Ids are persisted in
/// `MascotConfig` and double as asset-name stems, so their shape is pinned.
struct WardrobeCatalogTests {

    @Test func idsAreUnique() {
        let ids = WardrobeItem.catalogue.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// Asset names follow the id, one piece per canvas for a hat.
    @Test func assetNamesFollowTheID() {
        let cap = WardrobeItem.withID("item-hat-cap-red")!
        #expect(cap.bodyAssetName(on: .bust) == "item-hat-cap-red-bust")
        #expect(cap.bodyAssetName(on: .full) == "item-hat-cap-red-full")
        #expect(cap.limbAssetName(.left, on: .full) == nil)
    }

    /// A top is a torso plus a sleeve per arm, on both canvases — except the
    /// puffer vests, whose arms stay bare.
    @Test func topsSplitIntoTorsoAndSleeves() {
        let tee = WardrobeItem.withID("item-outfit-tee-white")!
        #expect(tee.bodyAssetName(on: .bust) == "item-outfit-tee-white-torso-bust")
        #expect(tee.limbAssetName(.left, on: .full) == "item-outfit-tee-white-sleeve-left-full")
        #expect(tee.limbAssetName(.right, on: .bust) == "item-outfit-tee-white-sleeve-right-bust")

        let vest = WardrobeItem.withID("item-outfit-puffer-red")!
        #expect(vest.bodyAssetName(on: .full) == "item-outfit-puffer-red-torso-full")
        #expect(vest.limbAssetName(.left, on: .full) == nil)
    }

    /// Pants and shoes only exist on the full body; skirts have no legs.
    @Test func pantsAndShoesAreFullBodyOnly() {
        let jeans = WardrobeItem.withID("item-pants-jeans-blue")!
        #expect(jeans.bodyAssetName(on: .full) == "item-pants-jeans-blue-hips-full")
        #expect(jeans.limbAssetName(.right, on: .full) == "item-pants-jeans-blue-leg-right-full")
        #expect(jeans.bodyAssetName(on: .bust) == nil)
        #expect(jeans.limbAssetName(.left, on: .bust) == nil)

        let skirt = WardrobeItem.withID("item-pants-skirt-pink")!
        #expect(skirt.bodyAssetName(on: .full) == "item-pants-skirt-pink-hips-full")
        #expect(skirt.limbAssetName(.left, on: .full) == nil)

        let sneakers = WardrobeItem.withID("item-shoes-sneakers-white")!
        #expect(sneakers.bodyAssetName(on: .full) == nil)
        #expect(sneakers.limbAssetName(.left, on: .full) == "item-shoes-sneakers-white-left-full")
        #expect(sneakers.limbAssetName(.right, on: .bust) == nil)
    }

    /// The README's rarities: sneakers are common, heels rare, the gold
    /// sneakers and the suit's and tuxedo's trousers epic.
    @Test func pantsAndShoesFollowThePackRarities() {
        let expected: [String: AchievementTier] = [
            "item-pants-jeans-blue": .bronze, "item-pants-shorts-khaki": .bronze,
            "item-pants-sweats-grey": .bronze, "item-shoes-sneakers-white": .bronze,
            "item-shoes-flats-pink": .bronze,
            "item-pants-trousers-charcoal": .silver, "item-pants-skirt-navy": .silver,
            "item-shoes-oxfords-black": .silver, "item-shoes-boots-brown": .silver,
            "item-shoes-heels-red": .silver,
            "item-pants-suit-classic": .gold, "item-pants-tuxedo-black": .gold,
            "item-shoes-sneakers-gold": .gold,
        ]
        for (id, tier) in expected {
            #expect(WardrobeItem.withID(id)?.tier == tier, "\(id)")
        }
    }

    /// The pack's hat rarities: every propeller and cap colour is common
    /// except the gold ones, which are the rare colourway.
    @Test func hatsFollowThePackRarities() {
        for id in ["item-hat-propeller-red", "item-hat-propeller-green", "item-hat-propeller-navy",
                   "item-hat-cap-red", "item-hat-beanie-red", "item-hat-bucket-green"] {
            #expect(WardrobeItem.withID(id)?.tier == .bronze, "\(id)")
        }
        for id in ["item-hat-fedora-tan", "item-hat-beret-black", "item-hat-cowboy-brown", "item-hat-graduation-black"] {
            #expect(WardrobeItem.withID(id)?.tier == .silver, "\(id)")
        }
        for id in ["item-hat-tophat-black", "item-hat-crown-gold", "item-hat-classic-navy"] {
            #expect(WardrobeItem.withID(id)?.tier == .gold, "\(id)")
        }
    }

    /// Only the puffers and the skirts go without limb layers.
    @Test func onlyVestsAndSkirtsLeaveLimbsBare() {
        let bare = WardrobeItem.catalogue.filter { !$0.coversLimbs }.map(\.id)
        #expect(Set(bare) == [
            "item-outfit-puffer-red", "item-outfit-puffer-navy",
            "item-pants-skirt-navy", "item-pants-skirt-pink",
        ])
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
            "item-glasses-aviator-gold", "item-glasses-aviator-silver",
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
        #expect(WardrobeItem.items(in: .outfit).count == 31)
        #expect(WardrobeItem.items(in: .pants).count == 12)
        #expect(WardrobeItem.items(in: .shoes).count == 12)
        #expect(WardrobeItem.items(in: .prop).isEmpty)
        #expect(WardrobeItem.items(in: .background).isEmpty)
    }

    /// The first eight hats shipped at these levels. Moving one later would
    /// strip it off a rat already wearing it, so they may only come earlier.
    @Test func theOriginalHatsNeverUnlockLater() {
        let pinned = [
            "item-hat-cap-red": 2, "item-hat-cap-green": 3, "item-hat-cap-navy": 5,
            "item-hat-propeller-red": 7, "item-hat-propeller-green": 9,
            "item-hat-propeller-navy": 12, "item-hat-cap-gold": 15, "item-hat-propeller-gold": 20,
        ]
        for (id, level) in pinned {
            #expect(WardrobeItem.withID(id)!.unlockLevel <= level, "\(id)")
        }
    }

    /// Every slot has a tab, once — except props, which have no art and no tab.
    @Test func everySlotButPropsHasATab() {
        #expect(Set(WardrobeSlot.tabOrder) == Set(WardrobeSlot.allCases).subtracting([.prop]))
        #expect(WardrobeSlot.tabOrder.count == WardrobeSlot.allCases.count - 1)
    }
}
