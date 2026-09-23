import Foundation
import SwiftData

/// Reminds the user to log the budget lines scheduled for today.
///
/// Everything here is derived from data, not kept in a queue: a line is
/// **due** when it lands on today and no live transaction logs that
/// occurrence yet. Two stamps on the line then decide how loudly to say so —
/// `reminderAnnouncedFor` (the toast has played today) and
/// `reminderAcknowledgedFor` (the user has looked at today in the calendar,
/// which clears the tab badge). Logging the occurrence, or deleting the line,
/// makes it stop being due and every trace of the reminder goes with it.
///
/// Only *today* reminds. A line from yesterday that was never logged stays
/// visible (un-greyed) in the calendar, but nagging about the past is the
/// kind of pressure the app avoids (see GAMIFICATION.md's principles).
enum BudgetReminderService {

    /// More than this many lines due on one day get one "N items" toast
    /// instead of a toast each — the same idea as the achievements batch.
    static let batchThreshold = 2

    /// The calendar every occurrence is resolved in. Gregorian on purpose:
    /// `BudgetItem`'s month/year numbers are Gregorian, and a device set to
    /// the Hebrew calendar would otherwise read "month 9" as Sivan.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "he_IL")
        return calendar
    }

    // MARK: - Reading

    /// Every occurrence that already has a live transaction logging it.
    /// Callers pass live rows only (`deletedAt == nil`), so a transaction in
    /// Recently Deleted un-greys its occurrence, and restoring it greys it
    /// again.
    static func loggedOccurrences(from transactions: [Transaction]) -> Set<BudgetOccurrence> {
        var result: Set<BudgetOccurrence> = []
        for transaction in transactions {
            guard let item = transaction.budgetItem,
                  let date = transaction.budgetOccurrenceDate else { continue }
            result.insert(BudgetOccurrence(
                itemID: item.persistentModelID,
                day: calendar.startOfDay(for: date)
            ))
        }
        return result
    }

    /// Start of the day `item` lands on within `day`'s month, if that is
    /// `day` itself — i.e. whether the line is scheduled for that day.
    static func occurrence(of item: BudgetItem, on day: Date) -> BudgetOccurrence? {
        let comps = calendar.dateComponents([.month, .year], from: day)
        guard let month = comps.month, let year = comps.year,
              let date = item.occurrenceDate(inMonth: month, year: year, calendar: calendar),
              calendar.isDate(date, inSameDayAs: day)
        else { return nil }
        return BudgetOccurrence(itemID: item.persistentModelID, day: calendar.startOfDay(for: day))
    }

    /// Lines scheduled for `day` that nothing has logged yet.
    static func dueItems(
        on day: Date,
        in items: [BudgetItem],
        logged: Set<BudgetOccurrence>
    ) -> [BudgetItem] {
        items.filter { item in
            guard let occurrence = occurrence(of: item, on: day) else { return false }
            return !logged.contains(occurrence)
        }
    }

    /// Whether the calendar tab should carry its reminder badge: something is
    /// due today that the user hasn't yet looked at in the calendar.
    static func needsAttention(_ due: [BudgetItem], on day: Date) -> Bool {
        due.contains { !isStamped($0.reminderAcknowledgedFor, on: day) }
    }

    /// The toast to play next, if any: the due lines whose toast hasn't
    /// played today — one at a time, or a single batch toast for a busy day.
    static func nextReminder(_ due: [BudgetItem], on day: Date) -> BudgetReminder? {
        let unannounced = due.filter { !isStamped($0.reminderAnnouncedFor, on: day) }
        guard let first = unannounced.first else { return nil }
        let covered = unannounced.count > batchThreshold ? unannounced : [first]
        return BudgetReminder(
            itemIDs: covered.map(\.persistentModelID),
            day: calendar.startOfDay(for: day),
            title: first.displayTitle,
            kind: first.kind,
            amount: first.plannedAmount,
            currencyCode: first.currencyCode
        )
    }

    // MARK: - Writing

    /// The toast for these lines has played; don't play it again today.
    ///
    /// Takes the models, not the reminder's ids, so the caller resolves them
    /// from a live `@Query` — a line deleted while its toast was up simply
    /// isn't in it, where `ModelContext.model(for:)` would hand back an
    /// object that traps on the write.
    static func markAnnounced(_ items: [BudgetItem], on day: Date, in context: ModelContext) {
        let start = calendar.startOfDay(for: day)
        for item in items {
            item.reminderAnnouncedFor = start
        }
        try? context.save()
    }

    /// The user has seen these lines in the calendar. Also counts as
    /// announced: a toast about something already on screen is noise.
    static func markAcknowledged(_ items: [BudgetItem], on day: Date, in context: ModelContext) {
        let start = calendar.startOfDay(for: day)
        var changed = false
        for item in items where !isStamped(item.reminderAcknowledgedFor, on: start) {
            item.reminderAcknowledgedFor = start
            item.reminderAnnouncedFor = start
            changed = true
        }
        if changed { try? context.save() }
    }

    // MARK: - Helpers

    private static func isStamped(_ stamp: Date?, on day: Date) -> Bool {
        guard let stamp else { return false }
        return calendar.isDate(stamp, inSameDayAs: day)
    }
}
