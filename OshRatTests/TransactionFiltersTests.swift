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
