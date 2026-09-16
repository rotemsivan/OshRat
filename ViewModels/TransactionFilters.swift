import Foundation
import SwiftData

/// The transactions list's filter state, plus the filtering itself.
///
/// It lives outside the view because `HomeView` rebuilds each tab's branch
/// from scratch when the user switches tabs — so anything held in
/// `TransactionsListView`'s own `@State` was reset the moment they looked at
/// the dashboard and came back. `HomeView` owns one of these for the session
/// and hands it down, which is what makes a filter *stay* set.
///
/// Session-scoped on purpose: not `@AppStorage`. A filter the user set a
/// minute ago is worth keeping; one they set last week, silently hiding most
/// of their ledger on a cold launch, is a bug report waiting to happen.
///
/// Having the predicate here as well as the state makes it testable — the view
/// keeps no filtering logic of its own.
@Observable
final class TransactionFilters {

    /// Free-text across title, note and category name.
    var search: String = ""
    var type: TypeFilter = .all
    var categoryID: PersistentIdentifier?
    var range: DateRangeFilter = .all
    var customStart: Date = .now.addingTimeInterval(-30 * 86400)
    var customEnd: Date = .now

    /// Whether any of the *sheet's* filters are on.
    ///
    /// Search is deliberately excluded: it has its own clear button in the
    /// search field, and it's already visible as typed text, so folding it in
    /// here would light up the toolbar's filter icon for something the user
    /// can plainly see.
    var hasActiveFilters: Bool {
        type != .all || categoryID != nil || range != .all
    }

    /// Reset the sheet's filters, leaving any search text alone — it's cleared
    /// separately, by the field's own button.
    func clear() {
        type = .all
        categoryID = nil
        range = .all
    }

    /// Reset everything, search included. Used when jumping to a transaction
    /// that the current filters would otherwise hide.
    func clearAll() {
        clear()
        search = ""
    }

    // MARK: - Filtering

    /// The filtered, still date-sorted subset of `transactions`.
    ///
    /// Client-side over the whole `@Query` result: the dataset is tiny by
    /// design (a hand-entered ledger, not a bank feed), so re-filtering on
    /// every keystroke is cheaper than maintaining a dynamic predicate.
    func apply(to transactions: [Transaction], now: Date = .now) -> [Transaction] {
        let needle = search
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let window = interval(now: now)

        return transactions.filter { tx in
            // Type (transfer-aware: income/expense exclude transfers, and the
            // transfer filter shows only them).
            guard type.matches(tx) else { return false }
            // Category
            if let categoryID, tx.category?.persistentModelID != categoryID { return false }
            // Date range
            if let window, !window.contains(tx.date) { return false }
            // Free-text
            if !needle.isEmpty {
                let haystack = [tx.title, tx.note, tx.category?.name ?? ""]
                    .joined(separator: " ")
                    .lowercased()
                if !haystack.contains(needle) { return false }
            }
            return true
        }
    }

    /// The date window implied by the current range filter. `nil` means "don't
    /// filter by date at all", which lets the pipeline above short-circuit.
    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        switch range {
        case .all:
            return nil
        case .last7:
            return DateInterval(start: now.addingTimeInterval(-7 * 86400), end: now)
        case .last30:
            return DateInterval(start: now.addingTimeInterval(-30 * 86400), end: now)
        case .last90:
            return DateInterval(start: now.addingTimeInterval(-90 * 86400), end: now)
        case .custom:
            // Cover *whole* days: the range pickers store each endpoint at
            // start-of-day, so without this a transaction logged later on the
            // end day would fall outside the range. Normalise to [start of the
            // first day, start of the day after the last] and let min/max
            // absorb a flipped pair.
            let lo = calendar.startOfDay(for: min(customStart, customEnd))
            let hiDay = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: hiDay) ?? hiDay
            return DateInterval(start: lo, end: end)
        }
    }
}

// MARK: - Filter options
//
// The two enums the filter is made of. Co-located with it rather than
// given files of their own: neither has any meaning apart from
// `TransactionFilters`, and they have to compile into the test target
// alongside it.

/// Four-way type filter. `.all` is the noop case that matches everything;
/// `.transfer` is its own bucket alongside income and expense.
enum TypeFilter: String, CaseIterable, Identifiable {
    case all
    case income
    case expense
    case transfer

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .all:      return "הכל"
        case .income:   return "הכנסה"
        case .expense:  return "הוצאה"
        case .transfer: return "העברה"
        }
    }

    /// Whether a transaction passes this filter. Transfers are stored with
    /// a placeholder `kind`, so `.income`/`.expense` explicitly exclude
    /// them (otherwise a transfer would leak into the expense list), and
    /// `.transfer` matches only them.
    func matches(_ tx: Transaction) -> Bool {
        switch self {
        case .all:      return true
        case .income:   return !tx.isTransfer && tx.kind == .income
        case .expense:  return !tx.isTransfer && tx.kind == .expense
        case .transfer: return tx.isTransfer
        }
    }
}

/// Coarse "how far back" buckets, plus a custom date-range escape hatch.
/// Snapped windows handle ~90% of "show me recent stuff"; custom covers
/// the "let me see July" case.
enum DateRangeFilter: String, CaseIterable, Identifiable {
    case all
    case last7
    case last30
    case last90
    case custom

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .all:    return "הכל"
        case .last7:  return "7 ימים"
        case .last30: return "30 ימים"
        case .last90: return "90 ימים"
        case .custom: return "טווח מותאם"
        }
    }
}
