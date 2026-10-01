import Testing
import Foundation
@testable import OshRat

/// The evening reminder's schedule and the quiet-day rules behind its button.
///
/// November 2026 has no holidays: Sun 1, Mon 2, Tue 3, Wed 4, Thu 5, Fri 6,
/// Sat 7, Sun 8, Mon 9.
@MainActor
struct DailyReminderTests {

    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func key(_ day: Int) -> String {
        XPRules.quietDayKey(for: date(2026, 11, day), calendar: calendar)
    }

    /// Deterministic shuffles (SplitMix64), so a failure reproduces.
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    // MARK: - Quiet days and the streak

    @Test func quietDayKeysAreGregorianDates() {
        #expect(Self.key(2) == "2026-11-02")
    }

    /// Monday logged, Tuesday quiet, Wednesday logged: the streak survives
    /// Tuesday but only Wednesday adds to it.
    @Test func aQuietDayBridgesWithoutExtending() {
        let kept = XPRules.nextStreak(
            current: 5, lastActivity: Self.date(2026, 11, 2), now: Self.date(2026, 11, 4),
            quietDays: [Self.key(3)], calendar: Self.calendar
        )
        let broken = XPRules.nextStreak(
            current: 5, lastActivity: Self.date(2026, 11, 2), now: Self.date(2026, 11, 4),
            calendar: Self.calendar
        )
        #expect(kept == 6)
        #expect(broken == 1)
    }

    @Test func quietDaysChainWithTheWeekend() {
        // Wed logged; Thu quiet; Fri–Sat weekend; Sun quiet; Mon logged.
        let streak = XPRules.nextStreak(
            current: 3, lastActivity: Self.date(2026, 11, 4), now: Self.date(2026, 11, 9),
            quietDays: [Self.key(5), Self.key(8)], calendar: Self.calendar
        )
        #expect(streak == 4)
    }

    // MARK: - Eligibility

    @Test func theWeekAllowsTwoQuietDays() {
        func eligibility(_ day: Int, _ marked: [Int]) -> QuietDayEligibility {
            XPRules.quietDayEligibility(
                on: Self.date(2026, 11, day, hour: 20),
                quietDays: Set(marked.map(Self.key)),
                hasActivityToday: false,
                calendar: Self.calendar
            )
        }
        #expect(eligibility(2, []) == .allowed(remainingAfter: 1))
        #expect(eligibility(3, [2]) == .allowed(remainingAfter: 0))
        #expect(eligibility(4, [2, 3]) == .weeklyLimitReached)
        // A new week starts on Sunday.
        #expect(eligibility(8, [2, 3]) == .allowed(remainingAfter: 1))
    }

    @Test func onlyAnUnloggedWorkingDayCanBeMarked() {
        let evening = Self.date(2026, 11, 4, hour: 20)
        #expect(XPRules.quietDayEligibility(
            on: evening, quietDays: [], hasActivityToday: true, calendar: Self.calendar
        ) == .alreadyLogged)
        #expect(XPRules.quietDayEligibility(
            on: evening, quietDays: [Self.key(4)], hasActivityToday: false, calendar: Self.calendar
        ) == .alreadyMarked)
        #expect(XPRules.quietDayEligibility(
            on: Self.date(2026, 11, 6, hour: 20), quietDays: [], hasActivityToday: false, calendar: Self.calendar
        ) == .restDay)
    }

    // MARK: - Which evenings remind

    @Test func workingDaysRemindAndTheWeekendDoesNot() {
        for day in 1...5 { #expect(DailyReminder.isReminderDay(Self.date(2026, 11, day), calendar: Self.calendar)) }
        #expect(!DailyReminder.isReminderDay(Self.date(2026, 11, 6), calendar: Self.calendar))
        #expect(!DailyReminder.isReminderDay(Self.date(2026, 11, 7), calendar: Self.calendar))
    }

    /// A weekday chag and its eve are both quiet. Found by search, so the
    /// test states its own premise.
    @Test func aChagAndItsEveDoNotRemind() throws {
        let chag = try #require((0..<400).lazy
            .map { Self.calendar.date(byAdding: .day, value: $0, to: Self.date(2026, 10, 1))! }
            .first { day in
                let eve = Self.calendar.date(byAdding: .day, value: -1, to: day)!
                return IsraeliHolidays.isBankHoliday(day)
                    && !XPRules.streakRestWeekdays.contains(Self.calendar.component(.weekday, from: day))
                    && !XPRules.isStreakRestDay(eve, calendar: Self.calendar)
            })
        let eve = Self.calendar.date(byAdding: .day, value: -1, to: chag)!
        #expect(!DailyReminder.isReminderDay(chag, calendar: Self.calendar))
        #expect(!DailyReminder.isReminderDay(eve, calendar: Self.calendar))
    }

    // MARK: - The schedule

    private func slots(
        from now: Date, skipToday: Bool = false, quietDays: Set<String> = [], seed: UInt64 = 1
    ) -> [DailyReminderSlot] {
        var rng = SeededRNG(state: seed)
        return DailyReminder.upcoming(
            from: now, skipToday: skipToday, quietDays: quietDays, calendar: Self.calendar, using: &rng
        )
    }

    @Test func todayIsIncludedOnlyBeforeSevenAndUntilHandled() {
        let wednesday = Self.date(2026, 11, 4)
        let thursday = Self.date(2026, 11, 5)
        #expect(slots(from: Self.date(2026, 11, 4, hour: 18)).first?.day == wednesday)
        #expect(slots(from: Self.date(2026, 11, 4, hour: 20)).first?.day == thursday)
        #expect(slots(from: Self.date(2026, 11, 4, hour: 9), skipToday: true).first?.day == thursday)
    }

    @Test func twoWeeksOfWorkingEveningsAtSeven() {
        let schedule = slots(from: Self.date(2026, 11, 1, hour: 8))
        #expect(schedule.count == DailyReminder.scheduleAhead)
        for slot in schedule {
            #expect(DailyReminder.isReminderDay(slot.day, calendar: Self.calendar))
            #expect(Self.calendar.component(.hour, from: slot.fireDate) == DailyReminder.hour)
        }
    }

    @Test func noPhraseRepeatsWithinTheWindow() {
        for seed in UInt64(1)...20 {
            let phrases = slots(from: Self.date(2026, 11, 1, hour: 8), seed: seed).map(\.phrase)
            #expect(Set(phrases).count == phrases.count)
        }
    }

    /// A week whose quiet days are spent gets no button — and so never the
    /// phrase that points at it.
    @Test func aSpentWeekOffersNoQuietDay() {
        // Two marks in each of the next three weeks.
        let marked: Set<String> = ["2026-11-01", "2026-11-02", "2026-11-08", "2026-11-09", "2026-11-15", "2026-11-16"]
        for seed in UInt64(1)...50 {
            let schedule = slots(from: Self.date(2026, 11, 3, hour: 8), quietDays: marked, seed: seed)
            for slot in schedule where slot.day < Self.date(2026, 11, 22) {
                #expect(!slot.offersQuietDay)
                #expect(slot.phrase != DailyReminder.quietDayHint)
            }
            #expect(schedule.contains { $0.offersQuietDay })
        }
    }

    // MARK: - Sync

    @Test func mergingKeepsEveryQuietDay() {
        let kept = UserProgress()
        kept.quietDays = ["2026-11-02"]
        let other = UserProgress()
        other.quietDays = ["2026-11-02", "2026-11-03"]
        kept.absorb(other)
        #expect(kept.quietDays == ["2026-11-02", "2026-11-03"])
    }
}
