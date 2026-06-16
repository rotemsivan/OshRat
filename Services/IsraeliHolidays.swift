import Foundation

/// One Israeli holiday on a given day.
///
/// `isRestDay` separates the two tiers: **rest days** (yom tov + Independence
/// Day — banks/workplaces closed) drive the income business-day shift, while
/// working-day holidays (Hanukkah, Purim, Tu BiShvat, Lag BaOmer) are shown
/// on the calendar but don't move a salary.
struct IsraeliHoliday: Hashable {
    let name: String
    let isRestDay: Bool
}

/// Computes the major Israeli holidays straight from the Hebrew calendar,
/// with no network and no hard-coded date tables.
///
/// Foundation's `.hebrew` calendar uses **fixed month numbers** for leap and
/// non-leap years alike — Tishrei = 1, Shevat = 5, Adar (II) = 7, Nisan = 8,
/// Iyar = 9, Sivan = 10, Kislev = 3 (a non-leap year simply omits month 6,
/// Adar I) — so the matches below need no leap-year handling. This was
/// verified empirically against known dates before relying on it.
enum IsraeliHolidays {
    private static let hebrew = Calendar(identifier: .hebrew)
    private static let gregorian = Calendar(identifier: .gregorian)

    /// The holiday falling on `date`, or `nil` if it isn't one.
    static func holiday(for date: Date) -> IsraeliHoliday? {
        let comps = hebrew.dateComponents([.year, .month, .day], from: date)
        guard let month = comps.month, let day = comps.day, let year = comps.year else { return nil }

        // MARK: Rest days (banks closed → drive the income shift)
        switch (month, day) {
        case (1, 1), (1, 2): return IsraeliHoliday(name: "ראש השנה", isRestDay: true)
        case (1, 10):        return IsraeliHoliday(name: "יום כיפור", isRestDay: true)
        case (1, 15):        return IsraeliHoliday(name: "סוכות", isRestDay: true)
        case (1, 22):        return IsraeliHoliday(name: "שמחת תורה", isRestDay: true)
        case (8, 15):        return IsraeliHoliday(name: "פסח", isRestDay: true)
        case (8, 21):        return IsraeliHoliday(name: "שביעי של פסח", isRestDay: true)
        case (10, 6):        return IsraeliHoliday(name: "שבועות", isRestDay: true)
        default:             break
        }
        // Independence Day — 5 Iyar (month 9), shifted off Fri/Sat/Mon by
        // Israel's observance law so it and Memorial Day avoid Shabbat.
        if month == 9, day == independenceDayIyarDay(hebrewYear: year) {
            return IsraeliHoliday(name: "יום העצמאות", isRestDay: true)
        }

        // MARK: Working-day holidays (shown only — salaries still pay)
        switch (month, day) {
        case (5, 15):  return IsraeliHoliday(name: "ט״ו בשבט", isRestDay: false)
        case (7, 14):  return IsraeliHoliday(name: "פורים", isRestDay: false)
        case (7, 15):  return IsraeliHoliday(name: "שושן פורים", isRestDay: false)
        case (9, 18):  return IsraeliHoliday(name: "ל״ג בעומר", isRestDay: false)
        default:       break
        }
        if isHanukkah(date, hebrewYear: year) {
            return IsraeliHoliday(name: "חנוכה", isRestDay: false)
        }
        return nil
    }

    /// Whether banks are closed on `date` (a rest-day holiday). Shabbat is
    /// handled separately by the caller. Used by the income business-day shift.
    static func isBankHoliday(_ date: Date) -> Bool {
        holiday(for: date)?.isRestDay == true
    }

    // MARK: - Internals

    /// Hanukkah is the eight days from 25 Kislev (month 3). Kislev is 29 or
    /// 30 days depending on the year, so we test membership by day-distance
    /// from the start rather than by fixed month/day pairs.
    private static func isHanukkah(_ date: Date, hebrewYear: Int) -> Bool {
        var comps = DateComponents()
        comps.calendar = hebrew
        comps.year = hebrewYear
        comps.month = 3
        comps.day = 25
        guard let start = hebrew.date(from: comps) else { return false }
        let diff = hebrew.dateComponents(
            [.day],
            from: hebrew.startOfDay(for: start),
            to: hebrew.startOfDay(for: date)
        ).day ?? -1
        return (0...7).contains(diff)
    }

    /// Observed day-of-Iyar for Independence Day. Base is 5 Iyar:
    ///   * Monday  → 6 Iyar (Tuesday)   — postponed
    ///   * Friday  → 4 Iyar (Thursday)  — advanced
    ///   * Saturday→ 3 Iyar (Thursday)  — advanced
    ///   * else    → 5 Iyar
    private static func independenceDayIyarDay(hebrewYear: Int) -> Int {
        var comps = DateComponents()
        comps.calendar = hebrew
        comps.year = hebrewYear
        comps.month = 9
        comps.day = 5
        guard let fifthIyar = hebrew.date(from: comps) else { return 5 }
        switch gregorian.component(.weekday, from: fifthIyar) {
        case 2: return 6
        case 6: return 4
        case 7: return 3
        default: return 5
        }
    }
}
