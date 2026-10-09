import Foundation

/// How the user's rat feels right now — a face (`bare-bust-rig-head-<mood>`),
/// a body pose and, for anything but calm, a line in a speech bubble saying
/// why. Shown on the dashboard greeting and the profile picture only; toasts
/// keep their own happy rat and the wardrobe rat stays neutral for dressing.
///
/// The rat reacts to **trends, not single days**. One evening off or one
/// spendy afternoon is life: it raises at most a worry. What moves him further
/// is a pattern — a week of luxuries well above the user's own usual, working
/// days going by unlogged, a second month over budget. Every unhappy mood is
/// still undone by something the user can do (log, mark the day quiet, ease
/// off for a few days), and a trend fades by itself as its window rolls on.
/// GAMIFICATION.md rules out a system that punishes; the rat nudges and
/// reacts, it doesn't hold a grudge.
enum MascotMood: String, CaseIterable {
    case calm, happy, worried, sad, angry

    /// The face's asset-name suffix; calm is the base head.
    var headSuffix: String {
        self == .calm ? "" : "-\(rawValue)"
    }
}

/// Why the rat feels the way it does — what the speech bubble says.
enum MascotMoodReason: Equatable {
    case none
    /// A level, a streak rung or a patch earned today.
    case celebrated
    /// Last month closed within budget, this one is on track and the logging
    /// is up to date.
    case keptBudget
    /// Late afternoon on a working day, nothing logged yet.
    case nothingLoggedYet
    /// The evening (`DailyReminder.hour`), still nothing.
    case nothingLoggedThisEvening
    /// `days` working days in a row with nothing logged, today included once
    /// its evening has come.
    case loggingLapsed(days: Int)
    /// This week's luxuries are running above the usual.
    case luxuriesRising
    /// This week's luxuries are far above the usual, on several days.
    case luxurySurge
    /// This month is over budget.
    case overBudget
    /// Over budget this month, as last month was.
    case overBudgetAgain

    /// The speech bubble's line, or `nil` for nothing to say.
    var line: String? {
        switch self {
        case .none: return nil
        case .celebrated: return String(localized: "יום של הישגים!")
        case .keptBudget: return String(localized: "החודש שעבר נסגר בתוך התקציב, וממשיכים ככה")
        case .nothingLoggedYet: return String(localized: "היום עוד לא רשמנו כלום…")
        case .nothingLoggedThisEvening: return String(localized: "כבר ערב, ועוד לא רשמנו כלום היום")
        case .loggingLapsed(let days): return String(localized: "כבר \(days) ימי עבודה בלי רישום…")
        case .luxuriesRising: return String(localized: "השבוע יותר מותרות מהרגיל")
        case .luxurySurge: return String(localized: "השבוע המותרות ממש בורחות לנו")
        case .overBudget: return String(localized: "החודש אנחנו מעל התקציב")
        case .overBudgetAgain: return String(localized: "שוב חודש מעל התקציב")
        }
    }
}

/// This week's luxury ("מותרות") spending against the user's usual week — the
/// trend the rat reads spending by, so a single treat never registers and a
/// week of them does. Amounts are in the preferred currency.
struct LuxuryTrend: Equatable {
    /// Luxury spending over the last `Rules.windowDays` days, today included.
    var recent: Decimal
    /// How many of those days had a luxury expense — a surge must be spread
    /// out, so one big purchase (a holiday, a gift) isn't read as a habit.
    var recentDays: Int
    /// A usual week's luxury spending: the weeks before the window, or, for a
    /// user without that much history, the budget's planned luxuries.
    var baseline: Decimal

    enum Rules {
        /// The window "this week" covers.
        static let windowDays = 7
        /// How many weeks before the window make up the usual.
        static let baselineWeeks = 8
        /// The fewest whole weeks of history before the window that count as
        /// a usual; below this the plan stands in (or nothing does).
        static let minimumBaselineWeeks = 3
        /// This week against the usual: worried from 1.5×, angry from 2×.
        static let risingRatio: Decimal = 1.5
        static let surgeRatio: Decimal = 2
        /// Days with a luxury the week needs for each.
        static let risingDays = 2
        static let surgeDays = 3
    }

    var isSurge: Bool { exceeds(Rules.surgeRatio, days: Rules.surgeDays) }
    var isRising: Bool { exceeds(Rules.risingRatio, days: Rules.risingDays) }

    private func exceeds(_ ratio: Decimal, days: Int) -> Bool {
        baseline > 0 && recentDays >= days && recent >= baseline * ratio
    }

    /// The trend from luxury expenses (`date`, amount in the preferred
    /// currency, in any order), or `nil` when there's nothing to compare
    /// against — too little history and no luxuries planned.
    ///
    /// - Parameters:
    ///   - historyStart: the day the user's ledger begins (their oldest row);
    ///     weeks before it aren't counted as zero-spend weeks.
    ///   - plannedMonthlyWants: this month's planned luxuries, the fallback
    ///     usual (scaled to a week).
    static func make(
        spends: [(date: Date, amount: Decimal)],
        historyStart: Date?,
        plannedMonthlyWants: Decimal,
        now: Date,
        calendar: Calendar = .current
    ) -> LuxuryTrend? {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let windowStart = calendar.date(byAdding: .day, value: 1 - Rules.windowDays, to: today) else { return nil }

        // Whole weeks of history before the window, up to `baselineWeeks`.
        var weeks = 0
        if let historyStart {
            let first = calendar.startOfDay(for: historyStart)
            let days = calendar.dateComponents([.day], from: first, to: windowStart).day ?? 0
            weeks = min(Rules.baselineWeeks, max(0, days / 7))
        }

        var recent = Decimal(0)
        var recentDays = Set<Date>()
        var before = Decimal(0)
        let baselineStart = calendar.date(byAdding: .day, value: -7 * weeks, to: windowStart) ?? windowStart
        for spend in spends where spend.date < tomorrow {
            if spend.date >= windowStart {
                recent += spend.amount
                recentDays.insert(calendar.startOfDay(for: spend.date))
            } else if spend.date >= baselineStart {
                before += spend.amount
            }
        }

        let baseline: Decimal
        if weeks >= Rules.minimumBaselineWeeks {
            baseline = before / Decimal(weeks)
        } else if plannedMonthlyWants > 0 {
            // A month is ~4.35 weeks (365.25 / 12 / 7).
            baseline = plannedMonthlyWants * 7 * 12 / Decimal(string: "365.25")!
        } else {
            return nil
        }
        return LuxuryTrend(recent: recent, recentDays: recentDays.count, baseline: baseline)
    }
}

/// What the mood is judged from — plain values, so the rules are testable
/// without a store. `HomeView` gathers them from the ledger and the progress
/// row.
struct MascotMoodFacts: Equatable {
    var now: Date
    /// Sun–Thu, not a chag or its eve (`DailyReminder.isReminderDay`) — the
    /// days the evening reminder runs, and so the days not logging matters.
    var isReminderDay: Bool
    /// Something counted for the streak today (`ProgressService.hasActivity`).
    var hasActivityToday: Bool
    var isQuietToday: Bool
    /// Working days before today, back to the last activity, that went by with
    /// nothing logged and no quiet mark (`MascotMood.missedWorkingDays`).
    var missedWorkingDays: Int = 0
    /// This week's luxuries against the usual; `nil` when there's no usual.
    var luxury: LuxuryTrend?
    /// Over this month's budget (`BudgetVsActual.hasOverrun`).
    var isOverBudget: Bool
    /// How last month closed against its plan; `nil` when it had none.
    var lastMonthKeptBudget: Bool?
    /// A celebration (level-up, achievement) was queued today.
    var celebratedToday: Bool
}

extension MascotMood {
    /// The tunable thresholds, in one place. The luxury ones are
    /// `LuxuryTrend.Rules`.
    enum Rules {
        /// From this hour a working day with nothing logged makes him
        /// worried; at `DailyReminder.hour` (19:00) the bubble says it's
        /// evening. Sadness needs a lapse of several days.
        static let worriedHour = 17
        /// Working days in a row without logging that make him sad. Today
        /// counts once its evening has come.
        static let lapsedDaysForSad = 2
        /// How far back `missedWorkingDays` looks — beyond this, more days
        /// say nothing new.
        static let lapseLookback = 14
    }

    /// The mood `facts` call for, and why. Strongest first: a surge of
    /// luxuries, then a logging lapse, then a day of celebrating, then the
    /// milder worries, then a good month.
    static func reading(for facts: MascotMoodFacts, calendar: Calendar = .current) -> (mood: MascotMood, reason: MascotMoodReason) {
        if facts.luxury?.isSurge == true {
            return (.angry, .luxurySurge)
        }

        let hour = calendar.component(.hour, from: facts.now)
        let unloggedToday = facts.isReminderDay && !facts.hasActivityToday && !facts.isQuietToday
        // Logging today closes a lapse; until then the days add up, and
        // today joins them once its evening has come.
        if !facts.hasActivityToday && !facts.isQuietToday {
            let lapsed = facts.missedWorkingDays + (unloggedToday && hour >= DailyReminder.hour ? 1 : 0)
            if lapsed >= Rules.lapsedDaysForSad {
                return (.sad, .loggingLapsed(days: lapsed))
            }
        }
        if facts.celebratedToday {
            return (.happy, .celebrated)
        }
        if unloggedToday, hour >= Rules.worriedHour {
            return (.worried, hour >= DailyReminder.hour ? .nothingLoggedThisEvening : .nothingLoggedYet)
        }
        if facts.isOverBudget {
            return (.worried, facts.lastMonthKeptBudget == false ? .overBudgetAgain : .overBudget)
        }
        if facts.luxury?.isRising == true {
            return (.worried, .luxuriesRising)
        }
        if facts.lastMonthKeptBudget == true, facts.missedWorkingDays == 0 {
            return (.happy, .keptBudget)
        }
        return (.calm, .none)
    }

    /// Working days strictly between the last activity and `now`'s day that
    /// weren't marked quiet — how long the logging has lapsed, today aside.
    /// Zero for a user who has never logged (onboarding is activity, so that
    /// is only a brand-new store) and capped at `Rules.lapseLookback` days back.
    static func missedWorkingDays(
        before now: Date,
        lastActivity: Date?,
        quietDays: Set<String>,
        calendar: Calendar = .current,
        isWorkingDay: (Date) -> Bool = { DailyReminder.isReminderDay($0) }
    ) -> Int {
        guard let lastActivity else { return 0 }
        let last = calendar.startOfDay(for: lastActivity)
        var day = calendar.startOfDay(for: now)
        var missed = 0
        for _ in 0..<Rules.lapseLookback {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day), previous > last else { break }
            day = previous
            if isWorkingDay(day), !quietDays.contains(XPRules.quietDayKey(for: day, calendar: calendar)) {
                missed += 1
            }
        }
        return missed
    }

    /// The hours of the day at which the mood can change with no data
    /// changing — the dashboard re-reads at each one.
    static var clockThresholds: [Int] { [Rules.worriedHour, DailyReminder.hour] }
}

#if DEBUG
/// A forced mood for testing, picked in the admin panel ("מצב רוח") and kept
/// in `UserDefaults` under `storageKey`, or via `-demoMood <mood>` — each one
/// a mood *and* the reason it gives, so every bubble line can be seen without
/// arranging the hour and the ledger to produce it.
enum MascotMoodScenario: String, CaseIterable, Identifiable {
    case calm, happy, happyKeptBudget, worriedNothingLogged, worriedOverBudget, worriedLuxuries, sad, angryLuxuries

    static let storageKey = "debug.mascotMoodScenario"

    var id: String { rawValue }

    var reading: (mood: MascotMood, reason: MascotMoodReason) {
        switch self {
        case .calm: return (.calm, .none)
        case .happy: return (.happy, .celebrated)
        case .happyKeptBudget: return (.happy, .keptBudget)
        case .worriedNothingLogged: return (.worried, .nothingLoggedYet)
        case .worriedOverBudget: return (.worried, .overBudgetAgain)
        case .worriedLuxuries: return (.worried, .luxuriesRising)
        case .sad: return (.sad, .loggingLapsed(days: 3))
        case .angryLuxuries: return (.angry, .luxurySurge)
        }
    }

    var title: String {
        switch self {
        case .calm: return "רגוע"
        case .happy: return "שמח · יום של הישגים"
        case .happyKeptBudget: return "שמח · חודש בתוך התקציב"
        case .worriedNothingLogged: return "מודאג · עוד לא נרשם כלום"
        case .worriedOverBudget: return "מודאג · שוב מעל התקציב"
        case .worriedLuxuries: return "מודאג · יותר מותרות מהרגיל"
        case .sad: return "עצוב · ימים בלי רישום"
        case .angryLuxuries: return "כועס · שבוע של מותרות"
        }
    }

    /// `-demoMood` takes a plain mood name; each maps to its first scenario.
    init?(mood: String) {
        switch MascotMood(rawValue: mood) {
        case .calm: self = .calm
        case .happy: self = .happy
        case .worried: self = .worriedNothingLogged
        case .sad: self = .sad
        case .angry: self = .angryLuxuries
        case nil: return nil
        }
    }
}
#endif
