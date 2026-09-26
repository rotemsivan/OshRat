import Testing
import Foundation
import SwiftData
@testable import OshRat

/// The transactions list's filter predicate.
///
/// Worth testing now that it lives outside the view: these are the rules that
/// decide whether a row the user is looking for is on screen at all.
@MainActor
struct TransactionFiltersTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: UserProfile.self, Account.self, Holding.self, Category.self,
                Transaction.self, TransactionAttachment.self, BudgetItem.self,
                Goal.self, FXRateSnapshot.self, UserProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Type

    @Test func transfersAreExcludedFromIncomeAndExpense() throws {
        let context = try Self.makeContext()
        let account = Account(name: "עו״ש", type: .current, currencyCode: "ILS")
        context.insert(account)

        let income = Transaction(amount: 100, kind: .income, account: account)
        let expense = Transaction(amount: 50, kind: .expense, account: account)
        // A transfer stores a placeholder `kind`, so it would leak into the
        // expense list if the filter went by `kind` alone.
        let transfer = Transaction(
            amount: 20, kind: .expense, account: account,
            destinationAccount: account, destinationAmount: 20
        )
        for tx in [income, expense, transfer] { context.insert(tx) }
        let all = [income, expense, transfer]

        let filters = TransactionFilters()

        filters.type = .income
        #expect(filters.apply(to: all).count == 1)

        filters.type = .expense
        let expenses = filters.apply(to: all)
        #expect(expenses.count == 1)
        #expect(expenses.first?.isTransfer == false)

        filters.type = .transfer
        let transfers = filters.apply(to: all)
        #expect(transfers.count == 1)
        #expect(transfers.first?.isTransfer == true)

        filters.type = .all
        #expect(filters.apply(to: all).count == 3)
    }

    // MARK: - Category

    @Test func categoryFilterMatchesOnIdentity() throws {
        let context = try Self.makeContext()
        let groceries = Category(name: "מכולת", kind: .expense)
        let transport = Category(name: "תחבורה", kind: .expense)
        context.insert(groceries)
        context.insert(transport)

        let a = Transaction(amount: 10, kind: .expense, category: groceries)
        let b = Transaction(amount: 20, kind: .expense, category: transport)
        let uncategorised = Transaction(amount: 30, kind: .expense)
        for tx in [a, b, uncategorised] { context.insert(tx) }
        try context.save()

        let filters = TransactionFilters()
        filters.categoryID = groceries.persistentModelID

        let result = filters.apply(to: [a, b, uncategorised])
        #expect(result.count == 1)
        #expect(result.first?.category?.name == "מכולת")
    }

    // MARK: - Date range

    /// The custom range stores each endpoint at start-of-day, so a row logged
    /// at lunchtime on the last day has to still fall inside it.
    @Test func customRangeCoversTheWholeEndDay() throws {
        let context = try Self.makeContext()
        let lateOnTheLastDay = Calendar.current.date(
            from: DateComponents(year: 2026, month: 3, day: 10, hour: 18, minute: 30)
        )!
        let tx = Transaction(amount: 10, kind: .expense, date: lateOnTheLastDay)
        context.insert(tx)

        let filters = TransactionFilters()
        filters.range = .custom
        filters.customStart = Self.date(2026, 3, 1)
        filters.customEnd = Self.date(2026, 3, 10)

        #expect(filters.apply(to: [tx]).count == 1)
    }

    /// A start and end the user managed to set backwards shouldn't silently
    /// match nothing.
    @Test func aFlippedCustomRangeStillMatches() throws {
        let context = try Self.makeContext()
        let tx = Transaction(amount: 10, kind: .expense, date: Self.date(2026, 3, 5))
        context.insert(tx)

        let filters = TransactionFilters()
        filters.range = .custom
        filters.customStart = Self.date(2026, 3, 10)
        filters.customEnd = Self.date(2026, 3, 1)

        #expect(filters.apply(to: [tx]).count == 1)
    }

    @Test func rollingWindowsExcludeOlderRows() throws {
        let context = try Self.makeContext()
        let now = Date.now
        let recent = Transaction(amount: 10, kind: .expense, date: now.addingTimeInterval(-2 * 86400))
        let old = Transaction(amount: 20, kind: .expense, date: now.addingTimeInterval(-40 * 86400))
        context.insert(recent)
        context.insert(old)

        let filters = TransactionFilters()
        filters.range = .last7
        #expect(filters.apply(to: [recent, old], now: now).count == 1)

        filters.range = .last90
        #expect(filters.apply(to: [recent, old], now: now).count == 2)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Rolling windows are whole days, today included: at 15:00, "the last 7
    /// days" must still take the whole of the oldest day, or that day's group
    /// in the list would show up half-empty.
    @Test func rollingWindowsCoverWholeDays() throws {
        let context = try Self.makeContext()
        let now = Self.date(2026, 3, 10, 15)
        let earlyOnTheOldestDay = Transaction(amount: 1, kind: .expense, date: Self.date(2026, 3, 4, 9))
        let lateTheDayBefore = Transaction(amount: 2, kind: .expense, date: Self.date(2026, 3, 3, 23, 30))
        let laterToday = Transaction(amount: 3, kind: .expense, date: Self.date(2026, 3, 10, 22))
        for tx in [earlyOnTheOldestDay, lateTheDayBefore, laterToday] { context.insert(tx) }

        let filters = TransactionFilters()
        filters.range = .last7
        let shown = filters.apply(to: [earlyOnTheOldestDay, lateTheDayBefore, laterToday], now: now)
        #expect(shown.map(\.amount) == [1, 3])
    }

    @Test func calendarPresetsFollowMonthAndYearBoundaries() throws {
        let context = try Self.makeContext()
        let now = Self.date(2026, 3, 10, 12)
        let lastDayOfFebruary = Transaction(amount: 1, kind: .expense, date: Self.date(2026, 2, 28, 23))
        let firstOfMarch = Transaction(amount: 2, kind: .expense, date: Self.date(2026, 3, 1, 0, 5))
        let lastYear = Transaction(amount: 3, kind: .expense, date: Self.date(2025, 12, 31, 20))
        let all = [firstOfMarch, lastDayOfFebruary, lastYear]
        for tx in all { context.insert(tx) }

        let filters = TransactionFilters()
        filters.range = .thisMonth
        #expect(filters.apply(to: all, now: now).map(\.amount) == [2])
        filters.range = .lastMonth
        #expect(filters.apply(to: all, now: now).map(\.amount) == [1])
        filters.range = .thisYear
        #expect(filters.apply(to: all, now: now).map(\.amount) == [2, 1])
    }

    /// Picking "custom" starts from the window already on screen, so it's one
    /// date to adjust — but never a date the capped pickers can't show.
    @Test func customRangeStartsFromThePresetAndStopsAtToday() {
        let calendar = TransactionFilters.calendar
        let now = Self.date(2026, 3, 10, 12)
        let filters = TransactionFilters()

        filters.range = .lastMonth
        filters.beginCustomRange(now: now)
        #expect(filters.range == .custom)
        #expect(calendar.isDate(filters.customStart, inSameDayAs: Self.date(2026, 2, 1)))
        #expect(calendar.isDate(filters.customEnd, inSameDayAs: Self.date(2026, 2, 28)))

        // "This month" runs to the 31st; the custom end stops at today.
        filters.range = .thisMonth
        filters.beginCustomRange(now: now)
        #expect(calendar.isDate(filters.customStart, inSameDayAs: Self.date(2026, 3, 1)))
        #expect(calendar.isDate(filters.customEnd, inSameDayAs: now))
    }

    @Test func rangeDescriptionSpellsOutTheWindow() {
        let filters = TransactionFilters()
        #expect(filters.rangeDescription() == nil)

        let now = Self.date(2026, 3, 10, 12)
        filters.range = .lastMonth
        // Both ends named, same year as now so no year printed.
        let description = filters.rangeDescription(now: now) ?? ""
        #expect(description.contains("1"))
        #expect(description.contains("28"))
        #expect(description.contains("–"))
        #expect(!description.contains("2026"))

        // A one-day custom range names the day once.
        filters.range = .custom
        filters.customStart = Self.date(2025, 7, 4)
        filters.customEnd = Self.date(2025, 7, 4)
        let single = filters.rangeDescription(now: now) ?? ""
        #expect(!single.contains("–"))
        #expect(single.contains("2025"))
    }

    // MARK: - Sort

    @Test func sortReordersWithoutDroppingRows() throws {
        let context = try Self.makeContext()
        // Newest first, as the query delivers them.
        let rows = [
            Transaction(amount: 50, kind: .expense, date: Self.date(2026, 3, 3)),
            Transaction(amount: 200, kind: .income, date: Self.date(2026, 3, 2)),
            Transaction(amount: 50, kind: .expense, date: Self.date(2026, 3, 1)),
            Transaction(amount: 10, kind: .expense, date: Self.date(2026, 2, 28))
        ]
        for tx in rows { context.insert(tx) }
        let byAmount: (Transaction) -> Decimal = { $0.amount }

        #expect(TransactionSort.newestFirst.apply(to: rows, amount: byAmount).map(\.amount) == [50, 200, 50, 10])
        #expect(TransactionSort.oldestFirst.apply(to: rows, amount: byAmount).map(\.amount) == [10, 50, 200, 50])

        let largest = TransactionSort.largestFirst.apply(to: rows, amount: byAmount)
        #expect(largest.map(\.amount) == [200, 50, 50, 10])
        // The two ₪50 rows tie and keep their date order (newer first).
        #expect(largest[1].date > largest[2].date)

        #expect(TransactionSort.smallestFirst.apply(to: rows, amount: byAmount).map(\.amount) == [10, 50, 50, 200])
    }

    /// Sort hides nothing, so it isn't a filter: it doesn't light the filter
    /// icon, and resetting the filters leaves it alone.
    @Test func sortIsNotAFilter() {
        let filters = TransactionFilters()
        filters.sort = .largestFirst
        #expect(filters.hasActiveFilters == false)

        filters.type = .expense
        filters.range = .thisMonth
        #expect(filters.activeFilterCount == 2)
        filters.clear()
        #expect(filters.activeFilterCount == 0)
        #expect(filters.sort == .largestFirst)
    }

    // MARK: - Search

    @Test func searchCoversTitleNoteAndCategoryName() throws {
        let context = try Self.makeContext()
        let category = Category(name: "מכולת", kind: .expense)
        context.insert(category)

        let byTitle = Transaction(amount: 10, kind: .expense, title: "קניות שבת")
        let byNote = Transaction(amount: 20, kind: .expense, title: "אחר", note: "קניות לבית")
        let byCategory = Transaction(amount: 30, kind: .expense, title: "אחר", category: category)
        let unrelated = Transaction(amount: 40, kind: .expense, title: "דלק")
        for tx in [byTitle, byNote, byCategory, unrelated] { context.insert(tx) }
        try context.save()

        let all = [byTitle, byNote, byCategory, unrelated]
        let filters = TransactionFilters()

        filters.search = "קניות"
        #expect(filters.apply(to: all).count == 2)

        filters.search = "מכולת"
        #expect(filters.apply(to: all).count == 1)

        // Whitespace-only is not a search.
        filters.search = "   "
        #expect(filters.apply(to: all).count == 4)
    }

    // MARK: - Active state

    /// Search is excluded deliberately: it has its own visible clear button,
    /// so folding it in would light the toolbar's filter icon for something
    /// the user can already see.
    @Test func searchDoesNotCountAsAnActiveFilter() {
        let filters = TransactionFilters()
        filters.search = "קניות"
        #expect(filters.hasActiveFilters == false)

        filters.type = .income
        #expect(filters.hasActiveFilters)
    }

    @Test func clearLeavesSearchAloneButClearAllDoesNot() {
        let filters = TransactionFilters()
        filters.search = "קניות"
        filters.type = .income
        filters.range = .last30

        filters.clear()
        #expect(filters.hasActiveFilters == false)
        #expect(filters.search == "קניות")

        filters.clearAll()
        #expect(filters.search.isEmpty)
    }
}
