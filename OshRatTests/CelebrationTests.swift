import Testing
@testable import OshRat

/// `Celebration` round-trips through the strings persisted on
/// `UserProgress.pendingCelebrations`, so the format is pinned here.
struct CelebrationTests {

    @Test func everyCaseRoundTrips() {
        let cases: [Celebration] = [.levelUp(12), .achievement(id: "log-100"), .achievementBatch(count: 10)]
        for celebration in cases {
            #expect(Celebration(rawValue: celebration.rawValue) == celebration)
        }
    }

    /// The prefixes are persisted — a rename would orphan a queued toast.
    @Test func rawValuesAreStable() {
        #expect(Celebration.levelUp(3).rawValue == "level:3")
        #expect(Celebration.achievement(id: "streak-7").rawValue == "achievement:streak-7")
        #expect(Celebration.achievementBatch(count: 5).rawValue == "achievements:5")
    }

    /// An entry this build can't read is skipped, never a crash.
    @Test func unreadableEntriesDecodeToNil() {
        #expect(Celebration(rawValue: "") == nil)
        #expect(Celebration(rawValue: "level:") == nil)
        #expect(Celebration(rawValue: "level:abc") == nil)
        #expect(Celebration(rawValue: "achievement:") == nil)
        #expect(Celebration(rawValue: "confetti:1") == nil)
    }
}
