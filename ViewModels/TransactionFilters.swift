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

    /// Free-text across title, note, category, account names and amount —
    /// matched forgivingly, see `HebrewSearch`.
    var search: String = ""
    var type: TypeFilter = .all
    var categoryID: PersistentIdentifier?
    var range: DateRangeFilter = .all
    var customStart: Date = .now.addingTimeInterval(-30 * 86400)
    var customEnd: Date = .now
    /// Row order. Not a filter — it hides nothing — so it's left out of
    /// `hasActiveFilters` and survives `clear()`: resetting the filters (or a
    /// jump that has to reveal a hidden row) shouldn't also re-sort the list
    /// out from under the user.
    var sort: TransactionSort = .newestFirst

    /// Each row's normalized search text, kept across searches (and tab
    /// switches). Not observed: it's a cache, and filling it during a render
    /// must not schedule another one.
    @ObservationIgnored private let searchIndex = TransactionSearchIndex()

    /// The calendar every date window is cut in. Gregorian on purpose, like
    /// the budget calendar: on a device set to the Hebrew calendar,
    /// `Calendar.current` would make "this month" a Hebrew month while every
    /// date the app prints is Gregorian.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    /// Whether any of the *sheet's* filters are on.
    ///
    /// Search is deliberately excluded: it has its own clear button in the
    /// search field, and it's already visible as typed text, so folding it in
    /// here would light up the toolbar's filter icon for something the user
    /// can plainly see.
    var hasActiveFilters: Bool {
        activeFilterCount > 0
    }

    /// How many of the sheet's filters are on — each is one removable chip in
    /// the list's top row, and two or more earn a "clear all" chip as well.
    var activeFilterCount: Int {
        (type != .all ? 1 : 0) + (categoryID != nil ? 1 : 0) + (range != .all ? 1 : 0)
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
    func apply(to transactions: [Transaction], now: Date = .now) -> [Transaction] {
        results(for: transactions, now: now).rows
    }

    /// The rows the filters and search leave, in one pass over the ledger.
    ///
    /// Search is tiered. Rows matching as typed, or with a spelling variant,
    /// win outright; only when there are none does it fall back to rows that
    /// match by forgiving a typo — and `isApproximate` says so, so the list
    /// can tell the user it's showing near matches. Showing typo matches
    /// *alongside* real ones would bury "ירקן" under every word one letter
    /// away from it.
    ///
    /// - Parameter search: the text to search for, when the caller is holding
    ///   a debounced copy of `search`; `nil` uses `search` itself.
    func results(for transactions: [Transaction], search: String? = nil, now: Date = .now) -> TransactionSearchResults {
        let query = TransactionSearchQuery(search ?? self.search)
        let window = interval(now: now)

        var strict: [Transaction] = []
        var approximate: [Transaction] = []
        for tx in transactions {
            // Type (transfer-aware: income/expense exclude transfers, and the
            // transfer filter shows only them).
            guard type.matches(tx) else { continue }
            // Category
            if let categoryID, tx.category?.persistentModelID != categoryID { continue }
            // Date range — half-open, see `interval(now:calendar:)`.
            if let window, tx.date < window.start || tx.date >= window.end { continue }
            // Free-text
            guard let query else {
                strict.append(tx)
                continue
            }
            switch searchIndex.tier(of: tx, for: query) {
            case .exact?, .spelling?: strict.append(tx)
            case .typo?:              approximate.append(tx)
            case nil:                 break
            }
        }

        // Deleted rows and re-keyed inserts leave orphans behind; sweep them
        // once they clearly outnumber the live rows rather than every pass.
        if query != nil, searchIndex.count > transactions.count * 2 + 64 {
            searchIndex.prune(keeping: Set(transactions.map(\.persistentModelID)))
        }

        if query == nil || !strict.isEmpty {
            return TransactionSearchResults(rows: strict, isApproximate: false)
        }
        return TransactionSearchResults(rows: approximate, isApproximate: !approximate.isEmpty)
    }

    /// The date window implied by the current range filter, as **whole days**:
    /// `start` is the first day's midnight and `end` the midnight *after* the
    /// last day, read half-open (`start <= date < end`). Whole days because
    /// the list is grouped by day — a window cut at the current time of day
    /// would show the oldest day's group only partly filled. `nil` means
    /// "don't filter by date at all", which lets the pipeline short-circuit.
    func interval(now: Date = .now, calendar: Calendar = TransactionFilters.calendar) -> DateInterval? {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now

        /// The last `days` days, today included.
        func trailing(_ days: Int) -> DateInterval {
            let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
            return DateInterval(start: start, end: tomorrow)
        }

        switch range {
        case .all:
            return nil
        case .last7:
            return trailing(7)
        case .last30:
            return trailing(30)
        case .last90:
            return trailing(90)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)
        case .lastMonth:
            let previous = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return calendar.dateInterval(of: .month, for: previous)
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)
        case .custom:
            // The pickers store each endpoint at start-of-day, so the end day
            // has to run to the following midnight or a transaction logged
            // later that day would fall outside. min/max absorb a flipped pair.
            let first = calendar.startOfDay(for: min(customStart, customEnd))
            let last = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
            return DateInterval(start: first, end: end)
        }
    }

    /// Switch to a custom range, starting from whatever window was already
    /// showing — so "last month, but only up to the 20th" is one date to
    /// change rather than two. Called when the user picks "טווח מותאם".
    ///
    /// The end is capped at today, because the pickers are (a ledger only
    /// records the past) and "this month" otherwise runs to its last day.
    func beginCustomRange(now: Date = .now, calendar: Calendar = TransactionFilters.calendar) {
        if range != .custom, let window = interval(now: now, calendar: calendar) {
            let lastDay = calendar.date(byAdding: .day, value: -1, to: window.end) ?? window.start
            customStart = window.start
            customEnd = min(lastDay, calendar.startOfDay(for: now))
        }
        range = .custom
    }

    /// The window in words — "1 בספטמבר – 26 בספטמבר" — for the sheet to
    /// confirm what a preset covers and for a custom range's chip. The year
    /// appears only when it isn't this one, or the range crosses one. `nil`
    /// when there's no date filter.
    func rangeDescription(now: Date = .now, calendar: Calendar = TransactionFilters.calendar) -> String? {
        guard let window = interval(now: now, calendar: calendar) else { return nil }
        let first = window.start
        let last = calendar.date(byAdding: .day, value: -1, to: window.end) ?? first

        let showsYear = calendar.component(.year, from: first) != calendar.component(.year, from: last)
            || calendar.component(.year, from: last) != calendar.component(.year, from: now)
        var style = Date.FormatStyle.dateTime.day().month(.wide).locale(Locale(identifier: "he_IL"))
        style.calendar = calendar
        if showsYear { style = style.year() }

        if calendar.isDate(first, inSameDayAs: last) {
            return first.formatted(style)
        }
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }

    /// What the date chip in the list's top row says: the preset's own name,
    /// or the dates themselves for a custom range (whose name alone would
    /// tell the user nothing).
    func dateChipLabel(now: Date = .now) -> String {
        range == .custom ? (rangeDescription(now: now) ?? range.hebrewLabel) : range.hebrewLabel
    }
}

/// What the list shows: the rows, and whether they're only near matches.
struct TransactionSearchResults {
    let rows: [Transaction]
    /// No row matched the search as typed; these match by forgiving a typo.
    let isApproximate: Bool
}

// MARK: - Filter options
//
// The enums the list's query is made of. Co-located with it rather than
// given files of their own: none has any meaning apart from
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

/// One-tap date windows, plus a custom range for anything else.
///
/// Two kinds on purpose: **calendar** periods (this month, last month, this
/// year) are how a budget is thought about — "what did I spend in August" —
/// while **rolling** ones (the last N days) answer "what's been going on
/// lately" without caring where a month boundary falls. Case order is the
/// order the sheet lays them out in.
enum DateRangeFilter: String, CaseIterable, Identifiable {
    case all
    case thisMonth
    case lastMonth
    case thisYear
    case last7
    case last30
    case last90
    case custom

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .all:       return "כל הזמן"
        case .thisMonth: return "החודש"
        case .lastMonth: return "החודש שעבר"
        case .thisYear:  return "השנה"
        case .last7:     return "7 ימים אחרונים"
        case .last30:    return "30 ימים אחרונים"
        case .last90:    return "90 ימים אחרונים"
        case .custom:    return "טווח מותאם"
        }
    }
}

/// The order the list shows its rows in.
///
/// The query already hands rows over newest first, so the two date orders
/// cost nothing (as-is, or reversed). The amount orders are the only real
/// sort, and the only ones that drop the day headers: once rows are ranked by
/// size, consecutive rows come from different days and a header per row would
/// be noise — the row shows its own date instead.
enum TransactionSort: String, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst
    case largestFirst
    case smallestFirst

    var id: String { rawValue }

    var hebrewLabel: String {
        switch self {
        case .newestFirst:   return "מהחדש לישן"
        case .oldestFirst:   return "מהישן לחדש"
        case .largestFirst:  return "מהסכום הגבוה"
        case .smallestFirst: return "מהסכום הנמוך"
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst:   return "calendar.badge.clock"
        case .oldestFirst:   return "calendar"
        case .largestFirst:  return "arrow.down.to.line"
        case .smallestFirst: return "arrow.up.to.line"
        }
    }

    /// Whether rows are grouped under day headers in this order.
    var groupsByDay: Bool {
        self == .newestFirst || self == .oldestFirst
    }

    /// Order `rows`, which must arrive **newest first** (the query's order).
    ///
    /// - Parameter amount: the size a row is ranked by. A closure so the
    ///   caller can express every row in one currency first — ranking raw
    ///   amounts would put ₪150 above $100. Read once per row, never inside
    ///   the comparator: a currency conversion per comparison is what would
    ///   make ranking a long ledger crawl.
    func apply(to rows: [Transaction], amount: (Transaction) -> Decimal) -> [Transaction] {
        switch self {
        case .newestFirst:
            return rows
        case .oldestFirst:
            return Array(rows.reversed())
        case .largestFirst, .smallestFirst:
            let descending = self == .largestFirst
            // Ranked on a (Double, index) pair, then rows looked up by index.
            // Sorting `Decimal` keys with the rows carried along took ~140 ms
            // on a 20,000-row ledger — measured, and on every render while the
            // sort is active. `Decimal` comparison is the slow part, not the
            // currency conversion; a `Double` orders money amounts the same,
            // and a pair of plain values is far cheaper to shuffle than one
            // holding a model reference.
            var keyed = rows.indices.map { index in
                (key: NSDecimalNumber(decimal: amount(rows[index])).doubleValue, index: index)
            }
            keyed.sort { lhs, rhs in
                if lhs.key != rhs.key { return descending ? lhs.key > rhs.key : lhs.key < rhs.key }
                // Equal amounts keep their date order, so the ranking is
                // stable from one render to the next.
                return lhs.index < rhs.index
            }
            return keyed.map { rows[$0.index] }
        }
    }
}
