import Foundation

/// How the user's rat feels right now — a face (`bare-bust-rig-head-<mood>`),
/// a body pose and, for anything but calm, a line in a speech bubble saying
/// why. Shown on the dashboard greeting and the profile picture only; toasts
/// keep their own happy rat and the wardrobe rat stays neutral for dressing.
///
/// Nothing here lasts past the day it's about, and every unhappy mood is
/// undone by something the user can do — log, mark the day quiet — or simply
/// by tomorrow. GAMIFICATION.md rules out a system that punishes; the rat
/// nudges and reacts, it doesn't hold a grudge.
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
    /// Late afternoon on a working day, nothing logged yet.
    case nothingLoggedYet
    /// The evening (`DailyReminder.hour`), still nothing.
    case nothingLoggedThisEvening
    /// `MascotMood.Rules.luxuriesForAngry` or more luxury expenses today.
    case manyLuxuries(count: Int)
    /// Today's logging took the month over budget.
    case wentOverBudgetToday
    /// The month was already over budget before today.
    case overBudget

    /// The speech bubble's line, or `nil` for nothing to say.
    var line: String? {
        switch self {
        case .none: return nil
        case .celebrated: return String(localized: "יום של הישגים!")
        case .nothingLoggedYet: return String(localized: "היום עוד לא רשמנו כלום…")
        case .nothingLoggedThisEvening: return String(localized: "כבר ערב, ועוד לא רשמנו כלום היום")
        case .manyLuxuries(let count): return String(localized: "\(count) הוצאות על מותרות היום…")
        case .wentOverBudgetToday: return String(localized: "היום עברנו את התקציב של החודש")
        case .overBudget: return String(localized: "החודש אנחנו מעל התקציב")
        }
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
    /// Expenses dated today in a luxury ("מותרות") category.
    var luxuriesToday: Int
    /// Over this month's budget now, but not on what was logged before today.
    var wentOverBudgetToday: Bool
    /// Over this month's budget (`BudgetVsActual.hasOverrun`).
    var isOverBudget: Bool
    /// A celebration (level-up, achievement) was queued today.
    var celebratedToday: Bool
}

extension MascotMood {
    /// The tunable thresholds, in one place.
    enum Rules {
        /// Luxury expenses in one day that make the rat angry. Three, so one
        /// treat — or two — is just life.
        static let luxuriesForAngry = 3
        /// From this hour a working day with nothing logged makes him
        /// worried; from `DailyReminder.hour` (19:00), sad.
        static let worriedHour = 17
    }

    /// The mood `facts` call for, and why. Strongest first: today's
    /// overspending, then the evening with nothing logged, then a day of
    /// celebrating, then the milder worries.
    static func reading(for facts: MascotMoodFacts, calendar: Calendar = .current) -> (mood: MascotMood, reason: MascotMoodReason) {
        if facts.luxuriesToday >= Rules.luxuriesForAngry {
            return (.angry, .manyLuxuries(count: facts.luxuriesToday))
        }
        if facts.wentOverBudgetToday {
            return (.angry, .wentOverBudgetToday)
        }

        let hour = calendar.component(.hour, from: facts.now)
        let nothingLogged = facts.isReminderDay && !facts.hasActivityToday && !facts.isQuietToday
        if nothingLogged, hour >= DailyReminder.hour {
            return (.sad, .nothingLoggedThisEvening)
        }
        if facts.celebratedToday {
            return (.happy, .celebrated)
        }
        if nothingLogged, hour >= Rules.worriedHour {
            return (.worried, .nothingLoggedYet)
        }
        if facts.isOverBudget {
            return (.worried, .overBudget)
        }
        return (.calm, .none)
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
    case calm, happy, worriedNothingLogged, worriedOverBudget, sad, angryLuxuries, angryWentOver

    static let storageKey = "debug.mascotMoodScenario"

    var id: String { rawValue }

    var reading: (mood: MascotMood, reason: MascotMoodReason) {
        switch self {
        case .calm: return (.calm, .none)
        case .happy: return (.happy, .celebrated)
        case .worriedNothingLogged: return (.worried, .nothingLoggedYet)
        case .worriedOverBudget: return (.worried, .overBudget)
        case .sad: return (.sad, .nothingLoggedThisEvening)
        case .angryLuxuries: return (.angry, .manyLuxuries(count: MascotMood.Rules.luxuriesForAngry))
        case .angryWentOver: return (.angry, .wentOverBudgetToday)
        }
    }

    var title: String {
        switch self {
        case .calm: return "רגוע"
        case .happy: return "שמח · יום של הישגים"
        case .worriedNothingLogged: return "מודאג · עוד לא נרשם כלום"
        case .worriedOverBudget: return "מודאג · מעל התקציב"
        case .sad: return "עצוב · ערב בלי רישום"
        case .angryLuxuries: return "כועס · מותרות היום"
        case .angryWentOver: return "כועס · עבר היום את התקציב"
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
