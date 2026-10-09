import Testing
import Foundation
@testable import OshRat

/// The rat's mood rules. Wednesday 4 November 2026 is an ordinary working day.
@MainActor
struct MascotMoodTests {

    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!

    private static func facts(
        hour: Int,
        isReminderDay: Bool = true,
        logged: Bool = false,
        quiet: Bool = false,
        missed: Int = 0,
        luxury: LuxuryTrend? = nil,
        over: Bool = false,
        lastMonthKept: Bool? = nil,
        celebrated: Bool = false
    ) -> MascotMoodFacts {
        MascotMoodFacts(
            now: calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour))!,
            isReminderDay: isReminderDay,
            hasActivityToday: logged,
            isQuietToday: quiet,
            missedWorkingDays: missed,
            luxury: luxury,
            isOverBudget: over,
            lastMonthKeptBudget: lastMonthKept,
            celebratedToday: celebrated
        )
    }

    private static func reading(_ facts: MascotMoodFacts) -> (mood: MascotMood, reason: MascotMoodReason) {
        MascotMood.reading(for: facts, calendar: calendar)
    }

    private static func mood(_ facts: MascotMoodFacts) -> MascotMood {
        reading(facts).mood
    }

    private static func day(_ offset: Int, hour: Int = 12) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!)!
    }

    // MARK: - Nothing logged

    @Test func theDayStartsCalm() {
        #expect(Self.mood(Self.facts(hour: 10)) == .calm)
    }

    @Test func oneEmptyEveningOnlyWorriesHim() {
        #expect(Self.mood(Self.facts(hour: 16)) == .calm)
        #expect(Self.reading(Self.facts(hour: 17)).reason == .nothingLoggedYet)
        let evening = Self.reading(Self.facts(hour: 19))
        #expect(evening.mood == .worried)
        #expect(evening.reason == .nothingLoggedThisEvening)
    }

    @Test func aLapseOfWorkingDaysMakesHimSad() {
        // Yesterday missed: sad only once today's evening joins it.
        #expect(Self.mood(Self.facts(hour: 12, missed: 1)) == .calm)
        #expect(Self.reading(Self.facts(hour: 19, missed: 1)).reason == .loggingLapsed(days: 2))
        // Two missed already: sad from the morning.
        #expect(Self.reading(Self.facts(hour: 9, missed: 2)).reason == .loggingLapsed(days: 2))
    }

    @Test func loggingOrAQuietDayEndsALapse() {
        #expect(Self.mood(Self.facts(hour: 21, logged: true, missed: 4)) == .calm)
        #expect(Self.mood(Self.facts(hour: 21, quiet: true, missed: 4)) == .calm)
    }

    @Test func restDaysNeverWorryHim() {
        #expect(Self.mood(Self.facts(hour: 21, isReminderDay: false)) == .calm)
    }

    @Test func missedDaysCountWorkingDaysAfterTheLastActivity() {
        // Wednesday; last logged Sunday → Monday and Tuesday missed.
        let workdays: (Date) -> Bool = { ![6, 7].contains(Self.calendar.component(.weekday, from: $0)) }
        func missed(lastActivity: Date?, quiet: Set<String> = []) -> Int {
            MascotMood.missedWorkingDays(before: Self.now, lastActivity: lastActivity, quietDays: quiet,
                                         calendar: Self.calendar, isWorkingDay: workdays)
        }
        #expect(missed(lastActivity: Self.day(-3)) == 2)
        #expect(missed(lastActivity: Self.day(-1)) == 0)
        #expect(missed(lastActivity: Self.now) == 0)
        #expect(missed(lastActivity: nil) == 0)
        // A quiet Monday doesn't count.
        let monday = XPRules.quietDayKey(for: Self.day(-2), calendar: Self.calendar)
        #expect(missed(lastActivity: Self.day(-3), quiet: [monday]) == 1)
        // Last logged the Wednesday before: Thu, Sun, Mon, Tue (Fri/Sat rest).
        #expect(missed(lastActivity: Self.day(-7)) == 4)
    }

    // MARK: - Luxuries

    private static func trend(_ spends: [(Int, Decimal)], historyDays: Int?, planned: Decimal = 0) -> LuxuryTrend? {
        LuxuryTrend.make(
            spends: spends.map { (Self.day($0.0), $0.1) },
            historyStart: historyDays.map { Self.day(-$0) },
            plannedMonthlyWants: planned,
            now: Self.now,
            calendar: Self.calendar
        )
    }

    /// A steady ₪100 a week for eight weeks before the window, on Mondays.
    private static let usual: [(Int, Decimal)] = (1...8).map { (-7 * $0 - 2, 100) }

    @Test func aBusyDayOfTreatsIsntATrend() {
        // ₪300 of luxuries today alone — 3× the usual, but on one day.
        let trend = Self.trend(Self.usual + [(0, 100), (0, 100), (0, 100)], historyDays: 70)
        #expect(trend?.baseline == 100)
        #expect(trend?.isSurge == false)
        #expect(Self.mood(Self.facts(hour: 12, logged: true, luxury: trend)) == .calm)
    }

    @Test func aWeekOfTreatsAngersHim() {
        let trend = Self.trend(Self.usual + [(0, 80), (-2, 80), (-4, 80)], historyDays: 70)
        #expect(trend?.isSurge == true)
        #expect(Self.reading(Self.facts(hour: 12, logged: true, luxury: trend)).reason == .luxurySurge)
    }

    @Test func aRisingWeekWorriesHim() {
        let trend = Self.trend(Self.usual + [(0, 80), (-3, 80)], historyDays: 70)
        #expect(trend?.isRising == true)
        #expect(trend?.isSurge == false)
        #expect(Self.reading(Self.facts(hour: 12, logged: true, luxury: trend)).reason == .luxuriesRising)
    }

    @Test func spendingAtTheUsualPaceIsCalm() {
        let trend = Self.trend(Self.usual + [(0, 40), (-3, 40), (-5, 40)], historyDays: 70)
        #expect(trend?.isRising == false)
    }

    @Test func aShortHistoryLeansOnThePlan() {
        // Two weeks of history: too little for a usual, so the plan's ₪435 a
        // month (~₪100 a week) stands in.
        let planned = Self.trend([(0, 80), (-2, 80), (-4, 80)], historyDays: 14, planned: 435)
        #expect(planned?.isSurge == true)
        #expect(Self.trend([(0, 80), (-2, 80), (-4, 80)], historyDays: 14) == nil)
    }

    @Test func theUsualOnlyCountsWeeksWithHistory() {
        // Four weeks of history at ₪100 a week: the usual is ₪100, not ₪50.
        let trend = Self.trend(Array(Self.usual.prefix(4)), historyDays: 7 + 28)
        #expect(trend?.baseline == 100)
    }

    // MARK: - Budget

    @Test func overBudgetWorriesAndSaysSoTheSecondTime() {
        #expect(Self.reading(Self.facts(hour: 12, logged: true, over: true)).reason == .overBudget)
        let again = Self.reading(Self.facts(hour: 12, logged: true, over: true, lastMonthKept: false))
        #expect(again.mood == .worried)
        #expect(again.reason == .overBudgetAgain)
    }

    @Test func aKeptMonthMakesHimHappy() {
        #expect(Self.reading(Self.facts(hour: 12, logged: true, lastMonthKept: true)).reason == .keptBudget)
        // Not while this month is over, or the logging has lapsed.
        #expect(Self.mood(Self.facts(hour: 12, logged: true, over: true, lastMonthKept: true)) == .worried)
        #expect(Self.mood(Self.facts(hour: 12, logged: true, missed: 1, lastMonthKept: true)) == .calm)
    }

    // MARK: - Priorities

    @Test func aLapseOutweighsACelebration() {
        #expect(Self.mood(Self.facts(hour: 20, missed: 1, celebrated: true)) == .sad)
        #expect(Self.mood(Self.facts(hour: 20, logged: true, celebrated: true)) == .happy)
    }

    @Test func aCelebrationOutweighsAnOverrun() {
        #expect(Self.mood(Self.facts(hour: 12, logged: true, over: true, celebrated: true)) == .happy)
    }

    @Test func aSurgeOutweighsEverything() {
        let trend = Self.trend(Self.usual + [(0, 80), (-2, 80), (-4, 80)], historyDays: 70)
        #expect(Self.mood(Self.facts(hour: 20, missed: 3, luxury: trend, celebrated: true)) == .angry)
    }

    // MARK: - Speech

    @Test func onlyCalmHasNothingToSay() {
        let reasons: [MascotMoodReason] = [
            .celebrated, .keptBudget, .nothingLoggedYet, .nothingLoggedThisEvening,
            .loggingLapsed(days: 2), .luxuriesRising, .luxurySurge, .overBudget, .overBudgetAgain,
        ]
        #expect(MascotMoodReason.none.line == nil)
        for reason in reasons { #expect(reason.line?.isEmpty == false) }
    }

    @Test func calmUsesTheBaseHead() {
        #expect(MascotMood.calm.headSuffix == "")
        #expect(MascotMood.sad.headSuffix == "-sad")
    }

    @Test func celebrationTimesMergeToTheLatest() {
        let kept = UserProgress()
        kept.lastCelebrationAt = Date(timeIntervalSince1970: 100)
        let other = UserProgress()
        other.lastCelebrationAt = Date(timeIntervalSince1970: 200)
        kept.absorb(other)
        #expect(kept.lastCelebrationAt == Date(timeIntervalSince1970: 200))
    }
}
