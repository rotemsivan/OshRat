import Foundation

/// A month's planned spending in its two buckets — needs and wants, as
/// `BudgetVsActual` splits them — and the one rule for whether a month's real
/// spending stayed within it. Pure, so the dashboard's overrun check and the
/// budget achievements (`BudgetMonthCommitment`) read the same definition.
struct PlannedSpend: Equatable {
    /// `.need`, `.neutral` and uncategorised planned spending.
    var needs: Decimal
    /// `.want` planned spending.
    var wants: Decimal

    var total: Decimal { needs + wants }

    /// Over the total, or over a bucket that had a budget of its own. A
    /// bucket with nothing planned can't overrun alone, but its spending still
    /// counts toward the total. Nothing planned at all is never an overrun —
    /// a user who hasn't budgeted isn't told they went over.
    func isOverrun(actualNeeds: Decimal, actualWants: Decimal) -> Bool {
        (total > 0 && actualNeeds + actualWants > total)
            || (needs > 0 && actualNeeds > needs)
            || (wants > 0 && actualWants > wants)
    }

    /// There was a plan, and nothing overran it — what "חודש בתוך התקציב"
    /// asks of a month.
    func isKept(actualNeeds: Decimal, actualWants: Decimal) -> Bool {
        total > 0 && !isOverrun(actualNeeds: actualNeeds, actualWants: actualWants)
    }

    /// A change during the month may only make it harder: each bucket keeps
    /// the lower of the committed and the new plan. Cutting a planned
    /// expense tightens; adding one, or raising one, changes nothing.
    func tightened(by newPlan: PlannedSpend) -> PlannedSpend {
        PlannedSpend(needs: min(needs, newPlan.needs), wants: min(wants, newPlan.wants))
    }
}
