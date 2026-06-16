import Foundation
import SwiftData

/// One planned line in the user's budget: how much they intend to
/// earn or spend, and how often. Two flavours, distinguished by `kind`:
///
/// * **Income** — `kind = .income`, `name` holds the source label
///   ("משכורת", "עבודה צדדית"), `category` is usually nil.
/// * **Expense** — `kind = .expense`, `category` is required, `name` is
///   an optional free-text note (e.g. "ספר" for a barber under "טיפוח").
///
/// Most budget lines are monthly. `everyXWeeks` covers things like a
/// barber visit every 3 weeks; the dashboard uses `monthlyEquivalent`
/// to roll that into a single monthly total.
@Model
final class BudgetItem {
    /// Free-text label. For income, this is the source name; for
    /// expense, an optional clarifying note about this specific line.
    var name: String = ""

    /// Amount per occurrence. For monthly lines this is also the
    /// monthly total; for `everyXWeeks` lines it's the per-visit amount.
    /// Computed monthly equivalents go through `monthlyEquivalent`.
    var plannedAmount: Decimal = 0

    var kind: TransactionKind = TransactionKind.expense
    var currencyCode: String = "ILS"

    /// Stored raw value of the frequency kind enum; defaults to monthly
    /// because that's far and away the most common cadence.
    var frequencyKindRaw: String = BudgetFrequencyKind.monthly.rawValue

    /// Interval in weeks for `.everyXWeeks` lines. Ignored for monthly.
    /// Stored even when unused so old rows migrate cleanly.
    var frequencyWeeks: Int = 1

    // MARK: - Scheduling

    /// Raw value of the schedule kind. Defaults to recurring-monthly so
    /// every pre-existing budget row behaves exactly as before (it counts
    /// toward every month). See `BudgetScheduleKind`.
    var scheduleKindRaw: String = BudgetScheduleKind.recurringMonthly.rawValue

    /// Optional day-of-month (1...31) the line is pinned to — e.g. salary
    /// on the 10th, rent on the 2nd. `nil` means "no specific day", which
    /// is the historical behaviour for plain monthly budgets. Clamped to
    /// the month's real length when resolved to a date.
    var scheduleDay: Int?

    /// Month-of-year (1...12) for `.recurringYearly` and `.oneTime` lines.
    /// `nil` for plain monthly lines.
    var scheduleMonth: Int?

    /// Calendar year for `.oneTime` lines only. `nil` otherwise.
    var scheduleYear: Int?

    /// Optional end bound for recurring lines — the last month (inclusive)
    /// the line still applies. Stored as month + year because the limit is
    /// month-granular ("until January 2028"). `nil` = runs indefinitely.
    /// Ignored for `.oneTime`.
    var scheduleEndMonth: Int?
    var scheduleEndYear: Int?

    var category: Category?

    init(
        name: String = "",
        plannedAmount: Decimal = 0,
        kind: TransactionKind = .expense,
        currencyCode: String = "ILS",
        frequencyKind: BudgetFrequencyKind = .monthly,
        frequencyWeeks: Int = 1,
        scheduleKind: BudgetScheduleKind = .recurringMonthly,
        scheduleDay: Int? = nil,
        scheduleMonth: Int? = nil,
        scheduleYear: Int? = nil,
        scheduleEndMonth: Int? = nil,
        scheduleEndYear: Int? = nil,
        category: Category? = nil
    ) {
        self.name = name
        self.plannedAmount = plannedAmount
        self.kind = kind
        self.currencyCode = currencyCode
        self.frequencyKindRaw = frequencyKind.rawValue
        self.frequencyWeeks = frequencyWeeks
        self.scheduleKindRaw = scheduleKind.rawValue
        self.scheduleDay = scheduleDay
        self.scheduleMonth = scheduleMonth
        self.scheduleYear = scheduleYear
        self.scheduleEndMonth = scheduleEndMonth
        self.scheduleEndYear = scheduleEndYear
        self.category = category
    }

    // MARK: - Computed

    /// Typed view of the stored raw frequency kind. Fallback to monthly
    /// keeps old rows (pre-migration) working.
    var frequencyKind: BudgetFrequencyKind {
        get { BudgetFrequencyKind(rawValue: frequencyKindRaw) ?? .monthly }
        set { frequencyKindRaw = newValue.rawValue }
    }

    /// Per-month equivalent of this line, for rolling into dashboard
    /// totals. For weekly cadences we approximate "30 days in a month"
    /// because the user-facing question is "roughly per month", not "to
    /// the day exact". For example, every-3-weeks at ₪100 ≈ ₪143/month.
    var monthlyEquivalent: Decimal {
        switch frequencyKind {
        case .monthly:
            return plannedAmount
        case .everyXWeeks:
            let weeks = max(frequencyWeeks, 1)
            // 30 days/month divided by (weeks × 7) gives occurrences/month
            return plannedAmount * (Decimal(30) / Decimal(weeks * 7))
        }
    }

    // MARK: - Schedule

    /// Typed view of the stored schedule kind. Fallback to recurring
    /// monthly keeps migrated rows (which have no value yet) working.
    var scheduleKind: BudgetScheduleKind {
        get { BudgetScheduleKind(rawValue: scheduleKindRaw) ?? .recurringMonthly }
        set { scheduleKindRaw = newValue.rawValue }
    }

    /// Whether this line counts toward the budget of the given month.
    /// Recurring-monthly lines always do; yearly lines only in their
    /// month; one-time lines only in their exact month and year.
    func appliesTo(month: Int, year: Int) -> Bool {
        // Past the optional end bound? Then it no longer applies, whatever
        // the cadence. The end is inclusive — "until January 2028" still
        // includes January 2028.
        if let endMonth = scheduleEndMonth, let endYear = scheduleEndYear,
           (year, month) > (endYear, endMonth) {
            return false
        }
        switch scheduleKind {
        case .recurringMonthly:
            return true
        case .recurringYearly:
            return scheduleMonth == month
        case .oneTime:
            return scheduleMonth == month && scheduleYear == year
        }
    }

    /// The amount this line contributes to a *specific* month's budget.
    /// Recurring-monthly lines contribute their monthly equivalent every
    /// month; yearly and one-time lines drop their whole planned amount
    /// into the single month they land on, and nothing into the others.
    func plannedAmount(inMonth month: Int, year: Int) -> Decimal {
        guard appliesTo(month: month, year: year) else { return 0 }
        switch scheduleKind {
        case .recurringMonthly:
            return monthlyEquivalent
        case .recurringYearly, .oneTime:
            return plannedAmount
        }
    }

    /// The concrete calendar date this line lands on within the given
    /// month, or `nil` when it has no specific day (or doesn't apply that
    /// month). The day is clamped to the month's real length so "the 31st"
    /// resolves to Feb 28/29 rather than rolling into March.
    func occurrenceDate(
        inMonth month: Int,
        year: Int,
        calendar: Calendar = .current,
        shiftIncomeToBusinessDay: Bool = true
    ) -> Date? {
        guard appliesTo(month: month, year: year), let day = scheduleDay else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        guard let firstOfMonth = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else { return nil }
        comps.day = min(day, range.count)
        guard let base = calendar.date(from: comps) else { return nil }
        // Salaries reach the bank on a working day, so by default we nudge
        // *income* off Shabbat and Israeli holidays onto the next business
        // day (e.g. a 1st that lands on Saturday, or on Yom Kippur, shows on
        // the next open day). Expenses are left untouched, and the shift can
        // be turned off globally (see Settings).
        if kind == .income && shiftIncomeToBusinessDay {
            return Self.businessDay(onOrAfter: base, calendar: calendar)
        }
        return base
    }

    /// Returns `date` unchanged unless it falls on a non-business day, in
    /// which case it advances to the next business day. Israel's work week
    /// is Sunday–Friday, so Saturday (weekday 7) is skipped, as are the
    /// Israeli rest-day holidays (see `IsraeliHolidays`). Walks forward up
    /// to two weeks to clear back-to-back closures (e.g. a holiday abutting
    /// Shabbat).
    static func businessDay(onOrAfter date: Date, calendar: Calendar = .current) -> Date {
        var result = date
        var safety = 0
        while isNonBusinessDay(result, calendar: calendar), safety < 14 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: result) else { break }
            result = next
            safety += 1
        }
        return result
    }

    private static func isNonBusinessDay(_ date: Date, calendar: Calendar) -> Bool {
        calendar.component(.weekday, from: date) == 7 || IsraeliHolidays.isBankHoliday(date)
    }

    /// Short Hebrew description of the cadence, for budget rows and the
    /// calendar (e.g. "כל חודש ב-10", "מדי שנה בפברואר", "22 באוגוסט 2026").
    /// Delegates to `BudgetSchedule` so the model and the editor drafts
    /// never describe the same schedule two different ways.
    var scheduleDescription: String {
        BudgetSchedule(from: self).hebrewDescription(
            frequencyKind: frequencyKind,
            frequencyWeeks: frequencyWeeks
        )
    }

    /// The exact date of a one-time line, reconstructed from its stored
    /// day/month/year components. `nil` for recurring lines.
    var oneTimeDate: Date? {
        guard scheduleKind == .oneTime,
              let year = scheduleYear, let month = scheduleMonth, let day = scheduleDay
        else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return Calendar.current.date(from: comps)
    }

    /// First day of the end-bound month, reconstructed from the stored
    /// month + year. `nil` when the line has no end bound.
    var scheduleEndDate: Date? {
        guard let month = scheduleEndMonth, let year = scheduleEndYear else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        return Calendar.current.date(from: comps)
    }
}

// MARK: - BudgetSchedule (UI-side value type)

/// A plain, `Hashable` representation of a budget line's schedule, used by
/// the onboarding/editor drafts and the schedule editor UI. Bridges to and
/// from the flat fields persisted on `BudgetItem`.
///
/// Keeping the UI in value-type land (rather than binding straight to a
/// SwiftData `@Model`) matches the rest of the budget flow, where drafts
/// stay in memory until the user confirms a save.
struct BudgetSchedule: Hashable {
    var kind: BudgetScheduleKind = .recurringMonthly
    /// Day-of-month used by monthly and yearly cadences (1...31).
    var dayOfMonth: Int = 1
    /// Whether a monthly/yearly line is pinned to `dayOfMonth`. When false
    /// the line still counts toward the month, just without a calendar day.
    var usesSpecificDay: Bool = false
    /// Month-of-year (1...12) for the yearly cadence.
    var month: Int = Calendar.current.component(.month, from: .now)
    /// Exact date for the one-time cadence.
    var oneTimeDate: Date = .now
    /// Whether a recurring line stops at `endDate` (month-granular). Never
    /// applies to one-time lines.
    var hasEndDate: Bool = false
    /// Last month the recurring line runs (its month + year are used).
    var endDate: Date = BudgetSchedule.defaultEndDate

    /// Build the UI schedule from a persisted item.
    init(from item: BudgetItem) {
        kind = item.scheduleKind
        usesSpecificDay = item.scheduleDay != nil
        dayOfMonth = item.scheduleDay ?? 1
        month = item.scheduleMonth ?? Calendar.current.component(.month, from: .now)
        oneTimeDate = item.oneTimeDate ?? .now
        hasEndDate = item.scheduleEndMonth != nil
        endDate = item.scheduleEndDate ?? Self.defaultEndDate
    }

    init(
        kind: BudgetScheduleKind = .recurringMonthly,
        dayOfMonth: Int = 1,
        usesSpecificDay: Bool = false,
        month: Int = Calendar.current.component(.month, from: .now),
        oneTimeDate: Date = .now,
        hasEndDate: Bool = false,
        endDate: Date = BudgetSchedule.defaultEndDate
    ) {
        self.kind = kind
        self.dayOfMonth = dayOfMonth
        self.usesSpecificDay = usesSpecificDay
        self.month = month
        self.oneTimeDate = oneTimeDate
        self.hasEndDate = hasEndDate
        self.endDate = endDate
    }

    /// Default end shown when the user first flips on "ends on" — a year
    /// out, so the picker opens somewhere sensible.
    static var defaultEndDate: Date {
        Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    }

    /// Write this schedule back onto a persisted item, setting only the
    /// fields relevant to the chosen kind and clearing the rest so a row
    /// can never carry stale components from a previous kind.
    func apply(to item: BudgetItem) {
        item.scheduleKind = kind
        switch kind {
        case .recurringMonthly:
            item.scheduleDay = usesSpecificDay ? clampedDay : nil
            item.scheduleMonth = nil
            item.scheduleYear = nil
        case .recurringYearly:
            item.scheduleMonth = month
            item.scheduleDay = usesSpecificDay ? clampedDay : nil
            item.scheduleYear = nil
        case .oneTime:
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: oneTimeDate)
            item.scheduleYear = comps.year
            item.scheduleMonth = comps.month
            item.scheduleDay = comps.day
        }
        // End bound is only meaningful for recurring lines.
        if kind != .oneTime, hasEndDate {
            let comps = Calendar.current.dateComponents([.month, .year], from: endDate)
            item.scheduleEndMonth = comps.month
            item.scheduleEndYear = comps.year
        } else {
            item.scheduleEndMonth = nil
            item.scheduleEndYear = nil
        }
    }

    private var clampedDay: Int { min(max(dayOfMonth, 1), 31) }

    /// Canonical short Hebrew description of the cadence, reused by the
    /// model (`BudgetItem.scheduleDescription`) and by the onboarding/
    /// editor draft rows. `frequencyKind`/`frequencyWeeks` only matter for
    /// the recurring-monthly "every X weeks" case.
    func hebrewDescription(
        frequencyKind: BudgetFrequencyKind = .monthly,
        frequencyWeeks: Int = 1
    ) -> String {
        let base: String
        switch kind {
        case .recurringMonthly:
            if frequencyKind == .everyXWeeks {
                // Localized for the Hebrew dual: כל שבוע / כל שבועיים / כל N שבועות.
                base = String(localized: "כל \(max(frequencyWeeks, 1)) שבועות")
            } else {
                base = usesSpecificDay ? "כל חודש ב-\(clampedDay)" : "כל חודש"
            }
        case .recurringYearly:
            let monthName = Self.hebrewMonthName(month)
            base = usesSpecificDay ? "מדי שנה, ה-\(clampedDay) ב\(monthName)" : "מדי שנה ב\(monthName)"
        case .oneTime:
            // One-off lines are inherently bounded, so no "until" suffix.
            return oneTimeDate.formatted(
                .dateTime.locale(Locale(identifier: "he_IL")).day().month(.wide).year()
            )
        }

        guard hasEndDate else { return base }
        let comps = Calendar.current.dateComponents([.month, .year], from: endDate)
        let endMonthName = Self.hebrewMonthName(comps.month ?? 1)
        return "\(base) · עד \(endMonthName) \(String(comps.year ?? 0))"
    }

    static func hebrewMonthName(_ month: Int) -> String {
        var comps = DateComponents()
        comps.year = 2000
        comps.month = month
        comps.day = 1
        let date = Calendar.current.date(from: comps) ?? .now
        return date.formatted(.dateTime.locale(Locale(identifier: "he_IL")).month(.wide))
    }
}
