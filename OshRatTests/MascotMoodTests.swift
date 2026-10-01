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

    private static func facts(
        hour: Int,
        isReminderDay: Bool = true,
        logged: Bool = false,
        quiet: Bool = false,
        luxuries: Int = 0,
        wentOver: Bool = false,
        over: Bool = false,
        celebrated: Bool = false
    ) -> MascotMoodFacts {
        MascotMoodFacts(
            now: calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour))!,
            isReminderDay: isReminderDay,
            hasActivityToday: logged,
            isQuietToday: quiet,
            luxuriesToday: luxuries,
            wentOverBudgetToday: wentOver,
            isOverBudget: over,
            celebratedToday: celebrated
        )
    }

    private static func mood(_ facts: MascotMoodFacts) -> MascotMood {
        MascotMood.reading(for: facts, calendar: calendar).mood
    }

    // MARK: - Nothing logged

    @Test func theDayStartsCalm() {
        #expect(Self.mood(Self.facts(hour: 10)) == .calm)
    }

    @Test func worriedFromFiveSadFromSeven() {
        #expect(Self.mood(Self.facts(hour: 16)) == .calm)
        #expect(Self.mood(Self.facts(hour: 17)) == .worried)
        #expect(Self.mood(Self.facts(hour: 19)) == .sad)
        #expect(MascotMood.reading(for: Self.facts(hour: 19), calendar: Self.calendar).reason == .nothingLoggedThisEvening)
    }

    @Test func aLogOrAQuietDayCalmsHim() {
        #expect(Self.mood(Self.facts(hour: 21, logged: true)) == .calm)
        #expect(Self.mood(Self.facts(hour: 21, quiet: true)) == .calm)
    }

    @Test func restDaysNeverMakeHimSad() {
        #expect(Self.mood(Self.facts(hour: 21, isReminderDay: false)) == .calm)
    }

    // MARK: - Spending

    @Test func threeLuxuriesMakeHimAngry() {
        #expect(Self.mood(Self.facts(hour: 12, logged: true, luxuries: 2)) == .calm)
        let reading = MascotMood.reading(for: Self.facts(hour: 12, logged: true, luxuries: 3), calendar: Self.calendar)
        #expect(reading.mood == .angry)
        #expect(reading.reason == .manyLuxuries(count: 3))
    }

    @Test func goingOverBudgetTodayAngersStayingOverWorries() {
        #expect(Self.mood(Self.facts(hour: 12, logged: true, wentOver: true, over: true)) == .angry)
        let lingering = MascotMood.reading(for: Self.facts(hour: 12, logged: true, over: true), calendar: Self.calendar)
        #expect(lingering.mood == .worried)
        #expect(lingering.reason == .overBudget)
    }

    // MARK: - Priorities

    @Test func anEveningWithNothingLoggedOutweighsACelebration() {
        #expect(Self.mood(Self.facts(hour: 20, celebrated: true)) == .sad)
        #expect(Self.mood(Self.facts(hour: 20, logged: true, celebrated: true)) == .happy)
    }

    @Test func aCelebrationOutweighsAnOldOverrun() {
        #expect(Self.mood(Self.facts(hour: 12, logged: true, over: true, celebrated: true)) == .happy)
    }

    @Test func overspendingTodayOutweighsEverything() {
        #expect(Self.mood(Self.facts(hour: 20, luxuries: 4, celebrated: true)) == .angry)
    }

    // MARK: - Speech

    @Test func onlyCalmHasNothingToSay() {
        let reasons: [MascotMoodReason] = [
            .celebrated, .nothingLoggedYet, .nothingLoggedThisEvening,
            .manyLuxuries(count: 3), .wentOverBudgetToday, .overBudget,
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
