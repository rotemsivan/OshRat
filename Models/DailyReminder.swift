import Foundation

/// One evening reminder, ready to hand to the notification centre.
struct DailyReminderSlot: Equatable {
    /// Start of the day it's for.
    let day: Date
    /// When it fires — `DailyReminder.hour` that day.
    let fireDate: Date
    let phrase: String
    /// Whether the notification carries the "לא היו היום תנועות" button —
    /// false once that week's quiet days are spent.
    let offersQuietDay: Bool
}

/// The evening reminder's rules: which days get one, and what it says.
///
/// Pure and tested; `DailyReminderService` turns its slots into local
/// notifications. A reminder is scheduled ahead for each working evening and
/// taken down once the day has activity (or is marked quiet), because iOS
/// can't wake an app at 19:00 to ask whether to remind — the notification has
/// to be waiting already.
enum DailyReminder {

    /// 19:00, after a working day and before the evening runs away.
    static let hour = 19

    /// How many evenings are scheduled ahead. Rescheduled on every launch, so
    /// only someone who doesn't open the app for three working weeks runs
    /// out — and by then a nightly reminder has stopped helping. Well under
    /// iOS's 64 pending notifications, with room for payment notifications.
    static let scheduleAhead = 14

    /// Sunday–Thursday, not a rest-day holiday, and not the **eve** of one:
    /// at 19:00 on Erev Rosh Hashanah the chag has already begun.
    static func isReminderDay(_ day: Date, calendar: Calendar = .current) -> Bool {
        guard !XPRules.isStreakRestDay(day, calendar: calendar) else { return false }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) else { return true }
        return !IsraeliHolidays.isBankHoliday(tomorrow)
    }

    /// The next `count` reminder evenings from `now`, each with a phrase.
    ///
    /// Today is included only while its 19:00 is still ahead and `skipToday`
    /// is false (the caller sets it once today has activity or is quiet).
    /// Phrases are dealt from a shuffled deck, so none repeats until the pool
    /// runs out.
    static func upcoming<R: RandomNumberGenerator>(
        from now: Date,
        skipToday: Bool,
        quietDays: Set<String>,
        count: Int = scheduleAhead,
        calendar: Calendar = .current,
        using rng: inout R
    ) -> [DailyReminderSlot] {
        var deck = phrases.shuffled(using: &rng)
        var slots: [DailyReminderSlot] = []
        let today = calendar.startOfDay(for: now)

        // Holidays can swallow a week (Sukkot), so look a little further
        // than `count` working days.
        for offset in 0..<(count * 3) where slots.count < count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
            else { continue }
            if offset == 0, skipToday || fire <= now { continue }
            guard isReminderDay(day, calendar: calendar) else { continue }

            let offers = XPRules.quietDaysUsed(inWeekOf: day, quietDays: quietDays, calendar: calendar)
                < XPRules.quietDaysPerWeek
            // The quiet-day hint only makes sense when the button is there,
            // so without it the hint is passed over (and stays in the deck).
            let usable = { (phrase: String) in offers || phrase != quietDayHint }
            if !deck.contains(where: usable) { deck += phrases.shuffled(using: &rng) }
            let phrase = deck.remove(at: deck.firstIndex(where: usable)!)
            slots.append(DailyReminderSlot(day: day, fireDate: fire, phrase: phrase, offersQuietDay: offers))
        }
        return slots
    }

    /// Points at the notification's own button, so it's only sent with one.
    static let quietDayHint = String(localized: "היום עבר בלי הוצאות בכלל? אפשר לסמן יום שקט ולשמור על הרצף")

    /// The pool. Gender-neutral, plural imperatives as elsewhere in the app,
    /// and never guilt — a nudge, in the spirit of GAMIFICATION.md.
    static let phrases: [String] = [
        String(localized: "כבר שבע בערב, זמן לתעד את ההוצאות היומיות"),
        String(localized: "אני רואה שאין היום תנועות בחשבון... זמן לתעד!"),
        String(localized: "יום ללא הוצאות הוא יום מבוזבז, זמן לעדכן את התנועות היומיות"),
        String(localized: "שבע בערב, הזמן הקבוע שלנו. מה נרשם היום?"),
        String(localized: "עוד לא נרשמה היום אף תנועה — אולי שכחנו משהו?"),
        String(localized: "היום כמעט נגמר, והיומן עוד מחכה. בואו נסגור אותו"),
        String(localized: "הקבלות מתקמטות בכיס... זמן להעביר אותן ליומן"),
        String(localized: "העכבר סופר פירורים. ספרו לו מה הוצאתם היום"),
        String(localized: "עכבר טוב לא מפספס אף פירור — גם לא הוצאה קטנה"),
        String(localized: "העכבר בודק את הארנק... ומוצא חורים ביומן. זמן לתעד"),
        String(localized: "דקה אחת עכשיו חוסכת שעה של ניחושים בסוף החודש"),
        String(localized: "שתי דקות של תיעוד = חודש בלי הפתעות"),
        String(localized: "הזיכרון נוטה לשכוח, היומן לא. זמן לרשום את התנועות של היום"),
        String(localized: "גם קפה של עשרה שקלים הוא חלק מהתמונה. זמן לתעד"),
        String(localized: "הסופר, הדלק, הקפה... הכול נרשם? זמן לבדוק"),
        String(localized: "לפני שהיום נגמר: מה נכנס ומה יצא?"),
        String(localized: "הכסף זז היום? בואו נראה לאן"),
        String(localized: "הוצאה שלא נרשמה היא הוצאה שהתקציב לא יודע עליה"),
        String(localized: "מי שסופר — שולט. זמן לרשום את הוצאות היום"),
        String(localized: "הרצף שלך מחכה לתנועה של היום"),
        String(localized: "היומן לא ימלא את עצמו... אבל זה ייקח רק דקה"),
        String(localized: "סוף יום עבודה, תחילת יום תיעוד. מה יצא היום מהארנק?"),
        String(localized: "ארוחת ערב? רגע לפני — תעדו את ההוצאות של היום"),
        String(localized: "התנועות של היום עדיין מסתובבות בראש? הכניסו אותן ליומן"),
        String(localized: "מספיקה דקה כדי שמחר תדעו בדיוק איפה אתם עומדים"),
        String(localized: "שליטה בכסף מתחילה בהרגל קטן אחד — התיעוד היומי"),
        String(localized: "סיכום יומי קטן, שקט נפשי גדול"),
        String(localized: "בלי לחץ, בלי שיפוט — רק לרשום מה היה היום"),
        String(localized: "התקציב שאל מה שלומכם היום. מה לענות לו?"),
        String(localized: "העו״ש לא משקר, אבל הוא גם לא מספר. ספרו לי מה היה היום"),
        String(localized: "תנועה אחת מתועדת שווה עשר שנשכחו"),
        String(localized: "היומן שלכם רעב לנתונים של היום"),
        String(localized: "הערב הוא הזמן הכי טוב לזכור על מה הלך הכסף היום"),
        String(localized: "עוד יום עבר, והיומן עדיין ריק. בואו נמלא אותו"),
        String(localized: "אין כמו לסיים את היום עם תמונה ברורה של הכסף"),
        String(localized: "זה הזמן לעצור רגע ולרשום את ההוצאות של היום"),
        String(localized: "בלי תיעוד אין שליטה. כמה שניות, וההוצאות של היום במקום"),
        String(localized: "עוד יום, עוד הזדמנות לראות לאן הולך הכסף"),
        String(localized: "ההוצאות של היום לא ייעלמו — אבל הזיכרון מהן כן. זמן לתעד"),
        quietDayHint,
    ]
}
