import Foundation
import SwiftData

/// A month's planned spending as the user committed to it: the budget as it
/// stood when the month began, tightened by any cut made during it, never
/// loosened. The budget achievements ("חודש בתוך התקציב" and the runs) judge
/// a month against this rather than against today's budget.
///
/// Why it exists: a month used to be judged against the *current* plan, so
/// every budget change anywhere had to disqualify every month from before it
/// — adding a forgotten income line in April cost February. With the plan
/// kept per month, a later edit can't rewrite a past verdict, and a change
/// during the month only counts when it makes the month harder (see
/// `BudgetCommitmentService`).
///
/// Planned figures are in `currencyCode`, the preferred currency when it was
/// captured; a month whose currency no longer matches isn't judged.
/// CloudKit-compatible: every property defaulted, no unique constraint — one
/// row per month is kept by the service, not the store.
@Model
final class BudgetMonthCommitment {
    var year: Int = 0
    var month: Int = 0
    /// Planned `.need`, `.neutral` and uncategorised spending — the needs
    /// bucket, as `BudgetVsActual` defines it.
    var plannedNeeds: Decimal = 0
    /// Planned `.want` spending.
    var plannedWants: Decimal = 0
    var currencyCode: String = "ILS"
    var capturedAt: Date = Date.now

    init(year: Int, month: Int, plannedNeeds: Decimal, plannedWants: Decimal, currencyCode: String, capturedAt: Date = .now) {
        self.year = year
        self.month = month
        self.plannedNeeds = plannedNeeds
        self.plannedWants = plannedWants
        self.currencyCode = currencyCode
        self.capturedAt = capturedAt
    }

    var yearMonth: YearMonth { YearMonth(year: year, month: month) }
}
