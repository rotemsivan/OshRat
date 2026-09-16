import Foundation
import SwiftData

/// The user's standing in the XP system — one row, for the one person using
/// the app.
///
/// Only *progress* is persisted here. The catalogue of what earns XP and what
/// each level costs lives in code (`XPRules`), per GAMIFICATION.md: keeping
/// the rules out of the database means rebalancing them later is an edit, not
/// a migration.
///
/// CloudKit rules as everywhere else — every stored property is optional or
/// defaulted, and there are no unique constraints — so turning sync on later
/// needs no rework here. (When that day comes, two devices could each create a
/// row; `ProgressService.progress(in:)` already resolves to the oldest one, so
/// the fix is a merge, not a crash.)
@Model
final class UserProgress {

    /// Lifetime XP. Never goes down: a missed day resets the streak, never the
    /// points. This is the number every level is derived from.
    var totalXP: Int = 0

    /// Consecutive days with logged activity, counting today.
    var currentStreak: Int = 0
    /// The best streak ever reached, kept as a personal record to beat.
    var longestStreak: Int = 0
    /// When activity was last recorded. Day-granular in effect — the streak
    /// maths normalises it to a day boundary.
    var lastActivityDate: Date?

    /// Keys of one-time awards already paid: setup milestones (an `XPReason`
    /// raw value) and streak rungs (`streak-7`). A plain `[String]` rather
    /// than a `Set` because SwiftData and CloudKit both take arrays without
    /// fuss, and the list stays short enough that membership checks are free.
    var awardedKeys: [String] = []

    /// XP produced today by the capped ("farmable") sources, and the day it
    /// belongs to. Stored rather than derived because there's no XP ledger to
    /// derive it from — phase 1 keeps only the running totals.
    var dailyCappedXP: Int = 0
    var dailyCapDate: Date?

    /// Set when an award pushes the user up a level; the dashboard raises the
    /// toast and clears it.
    ///
    /// Persisted, rather than handed back to the caller as a return value,
    /// because the level-up usually happens inside a sheet that is dismissing
    /// itself a moment later — the celebration has to outlive the screen that
    /// triggered it. A side effect is that a level-up earned just before the
    /// app was killed is still waiting on the next launch.
    var pendingLevelUpLevel: Int?

    /// The most recent award, so the card can always say what the last points
    /// were for. Stored as the raw value; read it back through `lastAwardReason`.
    var lastAwardReasonRaw: String?
    var lastAwardXP: Int = 0

    var createdAt: Date = Date.now

    init() {
        self.createdAt = .now
    }

    // MARK: - Derived

    /// Where this total sits inside the level curve.
    var levelProgress: LevelProgress {
        XPRules.progress(forTotalXP: totalXP)
    }

    var level: Int { levelProgress.level }

    /// The last award's reason, or `nil` before anything has been earned (or
    /// if a future build removes a case that's still stored here).
    var lastAwardReason: XPReason? {
        lastAwardReasonRaw.flatMap(XPReason.init(rawValue:))
    }

    /// Whether a one-time award has already been paid.
    func hasAwarded(key: String) -> Bool {
        awardedKeys.contains(key)
    }
}
