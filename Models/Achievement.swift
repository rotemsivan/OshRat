import Foundation

/// How rare an achievement is. Drives both the patch's look (phase 2's
/// shelf) and the XP it pays.
enum AchievementTier: String, CaseIterable {
    case bronze, silver, gold

    var hebrewLabel: String {
        switch self {
        case .bronze: return "ארד"
        case .silver: return "כסף"
        case .gold:   return "זהב"
        }
    }

    /// XP the tier pays on unlock — unless the achievement opts out (see
    /// `Achievement.paysXP`).
    var xp: Int {
        switch self {
        case .bronze: return 100
        case .silver: return 200
        case .gold:   return 300
        }
    }
}

/// The five themes the catalogue is grouped into, in the order a shelf would
/// show them.
enum AchievementGroup: String, CaseIterable {
    case consistency, discipline, growth, saving, hygiene

    var hebrewLabel: String {
        switch self {
        case .consistency: return "התמדה"
        case .discipline:  return "בקרה"
        case .growth:      return "צמיחה"
        case .saving:      return "חיסכון"
        case .hygiene:     return "סדר"
        }
    }
}

/// One entry in the achievements catalogue.
///
/// The catalogue is **code, not data** — GAMIFICATION.md is explicit that
/// only *progress* is persisted (`UserProgress.unlockedAchievements`), so a
/// rebalance is an edit rather than a migration. What each id actually
/// requires lives in `AchievementEvaluator`; this type is just the identity
/// card.
struct Achievement: Identifiable, Hashable {
    /// Persisted in `UserProgress.unlockedAchievements` — **never rename**.
    let id: String
    /// Final Hebrew text. The app is Hebrew-only, so the literal is the text,
    /// matching `XPReason.hebrewLabel`.
    let title: String
    let group: AchievementGroup
    let tier: AchievementTier
    /// SF Symbol drawn on the patch.
    let symbolName: String
    /// How to earn it, in one line — the shelf's "unlock hint". States the
    /// anti-farming spread where there is one, so an honest user who logged
    /// 100 rows in a week knows why the patch is still waiting.
    let hint: String
    /// False for the streak patches: `XPRules.streakMilestones` already pays
    /// for exactly those events, and paying twice for one act would be a bug.
    /// The patch is the reward.
    var paysXP: Bool = true
    /// False while the feature an achievement depends on doesn't exist. The
    /// entry stays in the catalogue — visible, unearned, and honestly not yet
    /// reachable — but `ProgressService` never unlocks it. Today that is the
    /// two goal patches, pending the Goals UI (ACHIEVEMENTS.md §8.6).
    var isReachable: Bool = true

    /// What unlocking this pays.
    var xpReward: Int { paysXP ? tier.xp : 0 }

    /// "ארד · +100 XP", shown under the title in the shelf's popover and the
    /// unlock toast. The XP is isolated left-to-right so the sign stays on the
    /// number's left, the same trick `LevelProgressCard` uses. Streak patches
    /// pay nothing — the streak bonus already paid — so they show the tier
    /// alone rather than a "+0".
    var rewardLine: String {
        guard xpReward > 0 else { return tier.hebrewLabel }
        return "\(tier.hebrewLabel) · \u{2066}+\(xpReward) XP\u{2069}"
    }
}

extension Achievement {

    /// The full catalogue, in shelf order. 24 entries; ACHIEVEMENTS.md §6 is
    /// the source of the criteria behind each id.
    static let catalogue: [Achievement] = [
        // התמדה — consistency
        Achievement(
            id: "streak-7", title: "שבוע רצוף", group: .consistency, tier: .bronze,
            symbolName: "flame.fill", hint: "7 ימים רצופים של רישום תנועות", paysXP: false
        ),
        Achievement(
            id: "streak-30", title: "חודש רצוף", group: .consistency, tier: .silver,
            symbolName: "flame.fill", hint: "30 ימים רצופים של רישום תנועות", paysXP: false
        ),
        Achievement(
            id: "streak-100", title: "מאה ימים", group: .consistency, tier: .gold,
            symbolName: "flame.fill", hint: "100 ימים רצופים של רישום תנועות", paysXP: false
        ),
        Achievement(
            id: "log-100", title: "מאה תנועות", group: .consistency, tier: .bronze,
            symbolName: "list.bullet.rectangle.fill", hint: "100 תנועות, שנרשמו לאורך 30 ימים לפחות"
        ),
        Achievement(
            id: "log-500", title: "חמש מאות תנועות", group: .consistency, tier: .silver,
            symbolName: "list.bullet.rectangle.fill", hint: "500 תנועות, שנרשמו לאורך 90 ימים לפחות"
        ),
        Achievement(
            id: "log-1000", title: "אלף תנועות", group: .consistency, tier: .gold,
            symbolName: "list.bullet.rectangle.fill", hint: "1,000 תנועות, שנרשמו לאורך 180 ימים לפחות"
        ),

        // בקרה — budget discipline
        Achievement(
            id: "under-budget-1", title: "חודש בתוך התקציב", group: .discipline, tier: .bronze,
            symbolName: "checkmark.shield.fill", hint: "חודש שלם בתוך התקציב, בלי לשנות את התקציב במהלכו"
        ),
        Achievement(
            id: "under-budget-3", title: "שלושה חודשים ברצף", group: .discipline, tier: .silver,
            symbolName: "checkmark.shield.fill", hint: "שלושה חודשים רצופים בתוך התקציב"
        ),
        Achievement(
            id: "under-budget-12", title: "שנה של משמעת", group: .discipline, tier: .gold,
            symbolName: "checkmark.shield.fill", hint: "שנים-עשר חודשים רצופים בתוך התקציב"
        ),
        Achievement(
            id: "wants-under-30", title: "רצונות מתחת ל-30%", group: .discipline, tier: .bronze,
            symbolName: "bag.fill", hint: "חודש שבו הרצונות היו פחות מ-30% מההוצאות"
        ),

        // צמיחה — growth
        Achievement(
            id: "surplus-3", title: "שלושה חודשים בעודף", group: .growth, tier: .bronze,
            symbolName: "chart.line.uptrend.xyaxis", hint: "שלושה חודשים רצופים שבהם ההכנסות עלו על ההוצאות"
        ),
        Achievement(
            id: "surplus-6", title: "חצי שנה בעודף", group: .growth, tier: .silver,
            symbolName: "chart.line.uptrend.xyaxis", hint: "שישה חודשים רצופים שבהם ההכנסות עלו על ההוצאות"
        ),
        Achievement(
            id: "surplus-12", title: "שנה בעודף", group: .growth, tier: .gold,
            symbolName: "chart.line.uptrend.xyaxis", hint: "שנה שלמה שבה כל חודש הסתיים בעודף"
        ),

        // חיסכון — saving
        Achievement(
            id: "first-deposit", title: "הפיקדון הראשון", group: .saving, tier: .bronze,
            symbolName: "banknote.fill", hint: "פיקדון עם ריבית, מועד פדיון וכסף בפנים"
        ),
        Achievement(
            id: "deposit-matured", title: "פיקדון עד הסוף", group: .saving, tier: .silver,
            symbolName: "hourglass.bottomhalf.filled", hint: "פיקדון שהגיע למועד הפדיון ונפדה"
        ),
        Achievement(
            id: "ladder-10", title: "סולם של עשר", group: .saving, tier: .silver,
            symbolName: "square.stack.3d.up.fill", hint: "10 הפקדות לפיקדון מתחדש, לאורך 5 חודשים לפחות"
        ),
        Achievement(
            id: "first-goal", title: "היעד הראשון", group: .saving, tier: .bronze,
            symbolName: "target", hint: "הגדרת יעד חיסכון ראשון", isReachable: false
        ),
        Achievement(
            id: "goal-done", title: "יעד הושג", group: .saving, tier: .silver,
            symbolName: "flag.checkered", hint: "השגת יעד, לפחות 30 יום אחרי שהוגדר", isReachable: false
        ),

        // סדר — hygiene
        Achievement(
            id: "categorised-50", title: "הכול מסודר", group: .hygiene, tier: .bronze,
            symbolName: "tag.fill", hint: "50 תנועות עם קטגוריה, לאורך 20 ימים לפחות"
        ),
        Achievement(
            id: "first-attachment", title: "קבלה ראשונה", group: .hygiene, tier: .bronze,
            symbolName: "paperclip", hint: "צירוף קבלה או מסמך לתנועה"
        ),
        Achievement(
            id: "attachments-25", title: "תיק מסמכים", group: .hygiene, tier: .silver,
            symbolName: "folder.fill", hint: "מסמכים מצורפים ל-25 תנועות שונות, לאורך 10 ימים לפחות"
        ),
        Achievement(
            id: "balance-check-10", title: "יתרות מעודכנות", group: .hygiene, tier: .bronze,
            symbolName: "scalemass.fill", hint: "10 עדכוני יתרה — לכל היותר אחד לחשבון ביום"
        ),
        Achievement(
            id: "first-transfer", title: "העברה ראשונה", group: .hygiene, tier: .bronze,
            symbolName: "arrow.left.arrow.right", hint: "העברה ראשונה בין חשבונות"
        ),
        Achievement(
            id: "multi-currency", title: "שני מטבעות", group: .hygiene, tier: .bronze,
            symbolName: "globe", hint: "תנועות בחשבונות בשני מטבעות שונים"
        ),
    ]

    /// Catalogue lookup by id. `nil` for an id a future build removed but
    /// which is still stored in `unlockedAchievements`.
    static func withID(_ id: String) -> Achievement? {
        catalogue.first { $0.id == id }
    }
}
