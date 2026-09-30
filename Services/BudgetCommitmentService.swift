import Foundation
import SwiftData

/// Keeps `BudgetMonthCommitment` — each month's planned spending as the user
/// committed to it — so the budget achievements can judge a month fairly:
///
/// - **Captured at the month's start.** Every month from the achievements
///   epoch to now gets its plan written down, as long as the budget hasn't
///   changed since that month began — so the plan written down *is* the one
///   that month started with. `captureMissing` runs on every achievements
///   evaluation (dashboard appear, every write point) and before every budget
///   change, so a month is normally captured the first time the app is opened
///   in it, before anything can be edited.
/// - **Tightened, never loosened.** A budget change goes through `change`,
///   which captures first, applies the change, then lets the *current*
///   month's plan only go down (`PlannedSpend.tightened`). Adding a forgotten
///   income line, planning next year's bill, or raising a limit mid-month no
///   longer costs anything; cutting a limit makes the month that much harder.
/// - **Past months are final.** A closed month keeps its plan, so a change in
///   April can't reach back and rewrite February.
///
/// A month the app never captured — the budget changed during it before this
/// existed, or no rate was available to express the plan — simply has no
/// commitment, and the evaluator falls back to the old, strict rule for it.
@MainActor
enum BudgetCommitmentService {

    /// Runs a budget change (add, edit or delete of a line) between the two
    /// halves of the bookkeeping, and saves.
    static func change(in context: ModelContext, now: Date = .now, _ body: () -> Void) {
        captureMissing(in: context, now: now)
        body()
        try? context.save()
        tightenCurrentMonth(in: context, now: now)
        try? context.save()
    }

    /// Writes down the plan of every month since the achievements epoch that
    /// has none yet, where the budget hasn't changed since the month began.
    /// The caller saves (or `change` does).
    static func captureMissing(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let progress = ProgressService.progress(in: context)
        guard let epoch = progress.achievementsEpoch else { return }
        let items = (try? context.fetch(FetchDescriptor<BudgetItem>())) ?? []
        let existing = Set(commitments(in: context).map(\.yearMonth))
        let lastChange = (items.compactMap(\.lastEditedAt) + [progress.budgetLastTouchedAt].compactMap { $0 }).max()
        let setting = currencySetting(in: context)

        var month = YearMonth(epoch, calendar: calendar)
        let current = YearMonth(now, calendar: calendar)
        while month <= current {
            defer { month = month.next }
            guard !existing.contains(month),
                  let start = month.start(in: calendar),
                  (lastChange ?? .distantPast) < start,
                  let plan = plannedSpend(for: month, items: items, setting: setting, calendar: calendar)
            else { continue }
            context.insert(BudgetMonthCommitment(
                year: month.year, month: month.month,
                plannedNeeds: plan.needs, plannedWants: plan.wants,
                currencyCode: setting.code, capturedAt: now
            ))
        }
    }

    /// The current month's commitment, lowered to the new plan wherever the
    /// new plan is lower.
    private static func tightenCurrentMonth(in context: ModelContext, now: Date, calendar: Calendar = .current) {
        let month = YearMonth(now, calendar: calendar)
        let setting = currencySetting(in: context)
        guard let commitment = commitments(in: context).first(where: { $0.yearMonth == month }),
              commitment.currencyCode == setting.code,
              let newPlan = plannedSpend(
                for: month,
                items: (try? context.fetch(FetchDescriptor<BudgetItem>())) ?? [],
                setting: setting,
                calendar: calendar
              )
        else { return }
        let tightened = PlannedSpend(needs: commitment.plannedNeeds, wants: commitment.plannedWants).tightened(by: newPlan)
        commitment.plannedNeeds = tightened.needs
        commitment.plannedWants = tightened.wants
    }

    /// Every commitment, one per month (the oldest row wins if a month was
    /// ever written twice).
    static func commitments(in context: ModelContext) -> [BudgetMonthCommitment] {
        let rows = (try? context.fetch(FetchDescriptor<BudgetMonthCommitment>(
            sortBy: [SortDescriptor(\.capturedAt)]
        ))) ?? []
        var seen: Set<YearMonth> = []
        return rows.filter { seen.insert($0.yearMonth).inserted }
    }

    /// The month's planned needs and wants in the preferred currency, from the
    /// same roll-up the dashboard card uses; `nil` when a line couldn't be
    /// converted, since a plan missing a line isn't the plan.
    private static func plannedSpend(
        for month: YearMonth,
        items: [BudgetItem],
        setting: (code: String, fx: FXRateSnapshot?),
        calendar: Calendar
    ) -> PlannedSpend? {
        guard let anchor = month.start(in: calendar) else { return nil }
        let report = BudgetVsActual(
            budgetItems: items,
            transactions: [],
            preferredCurrency: setting.code,
            fxSnapshot: setting.fx,
            scope: .month,
            calendar: calendar,
            now: anchor
        )
        guard !report.fxUnavailable else { return nil }
        return PlannedSpend(needs: report.needs.planned, wants: report.wants.planned)
    }

    private static func currencySetting(in context: ModelContext) -> (code: String, fx: FXRateSnapshot?) {
        var profile = FetchDescriptor<UserProfile>()
        profile.fetchLimit = 1
        var fx = FetchDescriptor<FXRateSnapshot>(sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)])
        fx.fetchLimit = 1
        return (
            (try? context.fetch(profile).first?.preferredCurrencyCode) ?? "ILS",
            try? context.fetch(fx).first
        )
    }
}
