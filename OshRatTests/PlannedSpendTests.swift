import Testing
import Foundation
@testable import OshRat

/// The "within budget" rule and the tighten-only commitment behind the
/// budget achievements.
struct PlannedSpendTests {

    private let plan = PlannedSpend(needs: 3000, wants: 1000)

    @Test func withinBothBucketsAndTheTotalIsKept() {
        #expect(plan.isKept(actualNeeds: 2900, actualWants: 950))
        #expect(!plan.isOverrun(actualNeeds: 2900, actualWants: 950))
    }

    /// Over one bucket's own budget is an overrun even under the total.
    @Test func oneBucketOverIsAnOverrun() {
        #expect(plan.isOverrun(actualNeeds: 2000, actualWants: 1100))
        #expect(!plan.isKept(actualNeeds: 2000, actualWants: 1100))
    }

    /// Spending in an unbudgeted bucket counts toward the total only.
    @Test func anUnbudgetedBucketCountsTowardTheTotal() {
        let needsOnly = PlannedSpend(needs: 3000, wants: 0)
        #expect(needsOnly.isKept(actualNeeds: 2500, actualWants: 400))
        #expect(!needsOnly.isKept(actualNeeds: 2800, actualWants: 400))
    }

    /// No plan, no verdict: nothing planned is neither kept nor overrun.
    @Test func nothingPlannedIsNeitherKeptNorOverrun() {
        let none = PlannedSpend(needs: 0, wants: 0)
        #expect(!none.isKept(actualNeeds: 100, actualWants: 0))
        #expect(!none.isOverrun(actualNeeds: 100, actualWants: 0))
    }

    /// Loosening mid-month changes nothing; cutting tightens; a shift between
    /// buckets keeps the lower of each.
    @Test func aChangeCanOnlyTighten() {
        #expect(plan.tightened(by: PlannedSpend(needs: 3500, wants: 1500)) == plan)
        #expect(plan.tightened(by: PlannedSpend(needs: 2800, wants: 1000)) == PlannedSpend(needs: 2800, wants: 1000))
        #expect(plan.tightened(by: PlannedSpend(needs: 2500, wants: 1500)) == PlannedSpend(needs: 2500, wants: 1000))
    }
}
