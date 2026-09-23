import Foundation
import SwiftData

/// One scheduled landing of a budget line: *this* line on *this* day.
///
/// A recurring line has many occurrences, and "logged" is a property of each
/// one, not of the line — paying this month's rent says nothing about next
/// month's. A transaction logged from the calendar or a reminder records the
/// occurrence it settles (`Transaction.budgetItem` + `budgetOccurrenceDate`),
/// and the calendar greys out exactly the occurrences in that set.
struct BudgetOccurrence: Hashable {
    let itemID: PersistentIdentifier
    /// Start of the scheduled day.
    let day: Date
}

/// What the reminder toast announces, as plain values.
///
/// A snapshot rather than the `BudgetItem` itself, for the hard-delete reason
/// in CLAUDE.md: the calendar deletes lines outright, and a toast still on
/// screen reading a deleted model's `name` would trap.
struct BudgetReminder: Hashable {
    /// The lines this toast covers — one, or several when a busy day is
    /// rolled into a single "N items today" toast.
    let itemIDs: [PersistentIdentifier]
    let day: Date
    /// Title, kind and amount of the first line; a single reminder shows
    /// them, a batch shows only the count.
    let title: String
    let kind: TransactionKind
    let amount: Decimal
    let currencyCode: String

    var isBatch: Bool { itemIDs.count > 1 }
}
