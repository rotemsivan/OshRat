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

    // MARK: - Recurrence (modern cadence model)

    /// Raw value of the recurrence unit ("every N <unit>"). **Optional on
    /// purpose:** `nil` marks a pre-`RecurrenceUnit` row, and `recurrenceUnit`
    /// then reconstructs the cadence from the legacy `frequencyKind`/
    /// `scheduleKind` fields. New rows always set it. (Optional + the count's
    /// default keep us CloudKit-safe and need no custom migration.)
    var recurrenceUnitRaw: String?

    /// The "N" in "every N <unit>" (e.g. 3 in "every 3 weeks"). Defaults to 1
    /// and is ignored on legacy rows (where `recurrenceUnitRaw` is `nil`).
    var recurrenceCount: Int = 1

    // MARK: - Legacy cadence (kept for migration only)

    /// Legacy frequency kind. Superseded by `recurrenceUnit`; read only as a
    /// fallback for rows persisted before the unit model existed.
    var frequencyKindRaw: String = BudgetFrequencyKind.monthly.rawValue

    /// Legacy weekly interval. Superseded by `recurrenceCount`; read only as a
    /// fallback for old `.everyXWeeks` rows.
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
        recurrenceUnit: RecurrenceUnit? = nil,
        recurrenceCount: Int = 1,
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
        self.recurrenceUnitRaw = recurrenceUnit?.rawValue
        self.recurrenceCount = recurrenceCount
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

    /// Typed view of the stored raw frequency kind. **Legacy** — kept for the
    /// recurrence fallback below. Fallback to monthly keeps old rows working.
    var frequencyKind: BudgetFrequencyKind {
        get { BudgetFrequencyKind(rawValue: frequencyKindRaw) ?? .monthly }
        set { frequencyKindRaw = newValue.rawValue }
    }

    /// The recurrence unit. Prefers the modern `recurrenceUnitRaw`; for rows
    /// that predate it, reconstructs the unit from the legacy schedule +
    /// frequency fields so historical budgets keep their original cadence.
    var recurrenceUnit: RecurrenceUnit {
        get {
            if let raw = recurrenceUnitRaw, let unit = RecurrenceUnit(rawValue: raw) {
                return unit
            }
            // Legacy fallback.
            switch scheduleKind {
            case .recurringYearly:
                return .year
            case .recurringMonthly:
                return frequencyKind == .everyXWeeks ? .week : .month
            case .oneTime:
                return .month // unused for one-time lines
            }
        }
        set { recurrenceUnitRaw = newValue.rawValue }
    }

    /// The "N" in "every N <unit>", never below 1. Falls back to the legacy
    /// `frequencyWeeks` for old weekly rows, otherwise 1.
    var recurrenceCountValue: Int {
        get {
            if recurrenceUnitRaw != nil { return max(recurrenceCount, 1) }
            // Legacy: only weekly rows carried a count, in `frequencyWeeks`.
            if scheduleKind == .recurringMonthly, frequencyKind == .everyXWeeks {
                return max(frequencyWeeks, 1)
            }
            return 1
        }
        set { recurrenceCount = max(newValue, 1) }
    }

    /// A one-time line is a single dated event rather than a recurring one.
    var isOneTime: Bool { scheduleKind == .oneTime }

    /// True when the line contributes to *every* month — either an averaged
    /// sub-monthly cadence or a plain "every month" line. Lines that land on
    /// select months only (yearly, every-N-months, one-time) return `false`.
    var landsEveryMonth: Bool {
        guard !isOneTime else { return false }
        if recurrenceUnit.isAveraged { return true }
        return recurrenceUnit == .month && recurrenceCountValue == 1
    }

    /// Whether the cadence is worth surfacing in a compact row — anything
    /// other than a plain "every month, no specific day" line.
    var hasNoteworthySchedule: Bool {
        isOneTime
            || recurrenceUnit != .month
            || recurrenceCountValue != 1
            || scheduleDay != nil
    }

    /// Per-month equivalent of this line. For **averaged** cadences (days/
    /// weeks) this is the smooth monthly figure the dashboard rolls up — we
    /// approximate "30 days in a month" since the question is "roughly per
    /// month", e.g. every-3-weeks at ₪100 ≈ ₪143/month. For **landing**
    /// cadences (months/years) it's the long-run average for reference only;
    /// the budget itself uses `plannedAmount(inMonth:year:)`, which drops the
    /// whole amount into the months the line actually occurs.
    var monthlyEquivalent: Decimal {
        let n = Decimal(recurrenceCountValue)
        switch recurrenceUnit {
        case .day:
            return plannedAmount * (Decimal(30) / n)
        case .week:
            // 30 days/month divided by (weeks × 7) gives occurrences/month.
            return plannedAmount * (Decimal(30) / (n * 7))
        case .month:
            return plannedAmount / n
        case .year:
            return plannedAmount / (n * 12)
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
    ///
    /// * Averaged cadences (days/weeks) and plain "every month" lines count
    ///   in every month.
    /// * "Every N months" lands on months whose distance from the anchor
    ///   month is a multiple of N; "every N years" lands in the anchor month
    ///   of every Nth year. `scheduleMonth`/`scheduleYear` hold that anchor.
    /// * One-time lines count only in their exact month and year.
    func appliesTo(month: Int, year: Int) -> Bool {
        // Past the optional end bound? Then it no longer applies, whatever
        // the cadence. The end is inclusive — "until January 2028" still
        // includes January 2028.
        if let endMonth = scheduleEndMonth, let endYear = scheduleEndYear,
           (year, month) > (endYear, endMonth) {
            return false
        }
        if isOneTime {
            return scheduleMonth == month && scheduleYear == year
        }
        let n = recurrenceCountValue
        switch recurrenceUnit {
        case .day, .week:
            return true
        case .month:
            guard n > 1 else { return true } // plain every-month line
            // Phase against the anchor (its absolute month index). Floored
            // modulo so months *before* the anchor stay in phase too.
            let anchorMonth = scheduleMonth ?? month
            let anchorYear = scheduleYear ?? year
            let delta = (year * 12 + month) - (anchorYear * 12 + anchorMonth)
            return Self.flooredMod(delta, n) == 0
        case .year:
            guard let anchorMonth = scheduleMonth, month == anchorMonth else { return false }
            guard n > 1 else { return true } // every year, in its month
            let anchorYear = scheduleYear ?? year
            return Self.flooredMod(year - anchorYear, n) == 0
        }
    }

    /// The amount this line contributes to a *specific* month's budget.
    /// Averaged cadences contribute their monthly equivalent every month;
    /// landing cadences (every N months/years) and one-time lines drop their
    /// whole planned amount into the months they occur in, and nothing else.
    func plannedAmount(inMonth month: Int, year: Int) -> Decimal {
        guard appliesTo(month: month, year: year) else { return 0 }
        if isOneTime { return plannedAmount }
        return recurrenceUnit.isAveraged ? monthlyEquivalent : plannedAmount
    }

    /// Floored modulo (result has the divisor's sign), so phase maths work
    /// for months/years on either side of the anchor. `n` is assumed ≥ 1.
    static func flooredMod(_ a: Int, _ n: Int) -> Int {
        let r = a % n
        return r >= 0 ? r : r + n
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
    /// calendar (e.g. "כל שבועיים", "כל חודש ב-10", "מדי שנה בפברואר",
    /// "22 באוגוסט 2026"). Delegates to `BudgetSchedule` so the model and the
    /// editor drafts never describe the same schedule two different ways.
    var scheduleDescription: String {
        BudgetSchedule(from: self).hebrewDescription()
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
    /// A one-time line is a single dated event; everything else recurs on
    /// `unit` + `count`.
    var isOneTime: Bool = false
    /// Recurrence interval: "every `count` `unit`s". Defaults to every month.
    var count: Int = 1
    var unit: RecurrenceUnit = .month
    /// Day-of-month a landing cadence is pinned to (1...31), when `usesSpecificDay`.
    var dayOfMonth: Int = 1
    /// Whether a landing line is pinned to `dayOfMonth`. When false the line
    /// still counts toward the month, just without a calendar day. Averaged
    /// cadences (days/weeks) never pin a day.
    var usesSpecificDay: Bool = false
    /// Month-of-year (1...12) a landing cadence occurs / anchors in (every N
    /// months with N>1, or any yearly cadence).
    var month: Int = Calendar.current.component(.month, from: .now)
    /// Year used as the phase anchor for landing cadences whose period
    /// doesn't divide evenly into a year (every 5 months, every 2 years…).
    var anchorYear: Int = Calendar.current.component(.year, from: .now)
    /// Exact date for the one-time cadence.
    var oneTimeDate: Date = .now
    /// Whether a recurring line stops at `endDate` (month-granular). Never
    /// applies to one-time lines.
    var hasEndDate: Bool = false
    /// Last month the recurring line runs (its month + year are used).
    var endDate: Date = BudgetSchedule.defaultEndDate

    /// Build the UI schedule from a persisted item.
    init(from item: BudgetItem) {
        isOneTime = item.isOneTime
        unit = item.recurrenceUnit
        count = item.recurrenceCountValue
        usesSpecificDay = item.scheduleDay != nil
        dayOfMonth = item.scheduleDay ?? 1
        month = item.scheduleMonth ?? Calendar.current.component(.month, from: .now)
        anchorYear = item.scheduleYear ?? Calendar.current.component(.year, from: .now)
        oneTimeDate = item.oneTimeDate ?? .now
        hasEndDate = item.scheduleEndMonth != nil
        endDate = item.scheduleEndDate ?? Self.defaultEndDate
    }

    init(
        isOneTime: Bool = false,
        count: Int = 1,
        unit: RecurrenceUnit = .month,
        dayOfMonth: Int = 1,
        usesSpecificDay: Bool = false,
        month: Int = Calendar.current.component(.month, from: .now),
        anchorYear: Int = Calendar.current.component(.year, from: .now),
        oneTimeDate: Date = .now,
        hasEndDate: Bool = false,
        endDate: Date = BudgetSchedule.defaultEndDate
    ) {
        self.isOneTime = isOneTime
        self.count = count
        self.unit = unit
        self.dayOfMonth = dayOfMonth
        self.usesSpecificDay = usesSpecificDay
        self.month = month
        self.anchorYear = anchorYear
        self.oneTimeDate = oneTimeDate
        self.hasEndDate = hasEndDate
        self.endDate = endDate
    }

    /// Default end shown when the user first flips on "ends on" — a year
    /// out, so the picker opens somewhere sensible.
    static var defaultEndDate: Date {
        Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    }

    /// True for anything other than a plain "every month, no specific day"
    /// line — i.e. worth surfacing in a compact row.
    var isNoteworthy: Bool {
        isOneTime || unit != .month || count != 1 || usesSpecificDay
    }

    /// Whether this cadence pins to a calendar month/day — i.e. lands its
    /// full amount on set months (every N>1 months, or yearly).
    private var landsOnAnchorMonth: Bool {
        !isOneTime && (unit == .year || (unit == .month && count > 1))
    }

    /// Write this schedule back onto a persisted item, setting only the
    /// fields relevant to the chosen cadence and clearing the rest so a row
    /// can never carry stale components from a previous cadence.
    func apply(to item: BudgetItem) {
        if isOneTime {
            // `scheduleKind` still flags one-time vs. recurring for all rows.
            item.scheduleKind = .oneTime
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: oneTimeDate)
            item.scheduleYear = comps.year
            item.scheduleMonth = comps.month
            item.scheduleDay = comps.day
        } else {
            // Keep the legacy kind sensible (yearly stays yearly) even though
            // the live cadence now reads from the recurrence fields.
            item.scheduleKind = unit == .year ? .recurringYearly : .recurringMonthly
            item.recurrenceUnit = unit
            item.recurrenceCountValue = count
            // Averaged cadences (days/weeks) are spread across the month, so
            // they never pin a calendar day — guard against a stale toggle
            // left on from a previous landing cadence.
            item.scheduleDay = (!unit.isAveraged && usesSpecificDay) ? clampedDay : nil
            // Only landing cadences need a month/year anchor; averaged and
            // plain-monthly lines clear it.
            item.scheduleMonth = landsOnAnchorMonth ? month : nil
            item.scheduleYear = landsOnAnchorMonth ? anchorYear : nil
        }
        // End bound is only meaningful for recurring lines.
        if !isOneTime, hasEndDate {
            let comps = Calendar.current.dateComponents([.month, .year], from: endDate)
            item.scheduleEndMonth = comps.month
            item.scheduleEndYear = comps.year
        } else {
            item.scheduleEndMonth = nil
            item.scheduleEndYear = nil
        }
    }

    private var clampedDay: Int { min(max(dayOfMonth, 1), 31) }

    /// "כל יום / כל שבועיים / כל 3 חודשים / כל שנה …" — the recurrence interval
    /// in Hebrew, handling the singular and dual forms. Shared by the cadence
    /// stepper and the full schedule description.
    static func everyPhrase(count: Int, unit: RecurrenceUnit) -> String {
        let n = max(count, 1)
        switch unit {
        case .day:   return n == 1 ? "כל יום"  : "כל \(n) ימים"
        case .week:  return n == 1 ? "כל שבוע" : n == 2 ? "כל שבועיים" : "כל \(n) שבועות"
        case .month: return n == 1 ? "כל חודש" : "כל \(n) חודשים"
        case .year:  return n == 1 ? "כל שנה"  : n == 2 ? "כל שנתיים"  : "כל \(n) שנים"
        }
    }

    /// Canonical short Hebrew description of the cadence, reused by the model
    /// (`BudgetItem.scheduleDescription`) and by the onboarding/editor draft
    /// rows, so a schedule is never described two different ways.
    func hebrewDescription() -> String {
        if isOneTime {
            // One-off lines are inherently bounded, so no "until" suffix.
            return oneTimeDate.formatted(
                .dateTime.locale(Locale(identifier: "he_IL")).day().month(.wide).year()
            )
        }

        let phrase = Self.everyPhrase(count: count, unit: unit)
        let base: String
        switch unit {
        case .day, .week:
            base = phrase
        case .month:
            if count == 1 {
                base = usesSpecificDay ? "כל חודש ב-\(clampedDay)" : "כל חודש"
            } else {
                base = usesSpecificDay ? "\(phrase), ב-\(clampedDay) בחודש" : phrase
            }
        case .year:
            let monthName = Self.hebrewMonthName(month)
            if count == 1 {
                base = usesSpecificDay ? "מדי שנה, ה-\(clampedDay) ב\(monthName)" : "מדי שנה ב\(monthName)"
            } else {
                base = usesSpecificDay ? "\(phrase), ה-\(clampedDay) ב\(monthName)" : "\(phrase) ב\(monthName)"
            }
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
