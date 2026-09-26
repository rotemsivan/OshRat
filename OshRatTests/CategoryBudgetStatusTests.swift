import Testing
import Foundation
import SwiftData
@testable import OshRat

/// One category's month against its budget — the bar in a transaction's
/// expanded card.
@MainActor
struct CategoryBudgetStatusTests {

    private static func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: UserProfile.self, Account.self, Holding.self, Category.self,
                Transaction.self, TransactionAttachment.self, BudgetItem.self,
                Goal.self, FXRateSnapshot.self, UserProgress.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        CategoryBudgetStatus.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// The example from the feature request: ₪1,000 a month for כלכלת בית.
    @Test func countsOnlyTheCategorysRealRowsInThatMonth() throws {
        let context = try Self.makeContext()
        let groceries = Category(name: "כלכלת בית", kind: .expense)
        let dining = Category(name: "מסעדות", kind: .expense)
        context.insert(groceries); context.insert(dining)
        context.insert(BudgetItem(plannedAmount: 1000, kind: .expense, category: groceries))
        context.insert(BudgetItem(plannedAmount: 400, kind: .expense, category: dining))

        // Newest first, as the list's query delivers them.
        let rows = [
            Transaction(amount: 90, kind: .expense, date: Self.date(2026, 10, 2), category: groceries),   // next month
            Transaction(amount: 300, kind: .expense, date: Self.date(2026, 9, 20), category: groceries),
            Transaction(amount: 55, kind: .expense, date: Self.date(2026, 9, 18), category: dining),      // other category
            Transaction(amount: 200, kind: .expense, date: Self.date(2026, 9, 1, 0), category: groceries), // first minute
            Transaction(amount: 70, kind: .expense, date: Self.date(2026, 8, 31, 23), category: groceries) // last month
        ]
        rows.forEach(context.insert)
        try context.save()

        let status = try #require(CategoryBudgetStatus.make(
            category: groceries,
            containing: Self.date(2026, 9, 20),
            budgetItems: try context.fetch(FetchDescriptor<BudgetItem>()),
            transactions: rows,
            preferredCurrency: "ILS",
            fxSnapshot: nil
        ))
        #expect(status.planned == 1000)
        #expect(status.actual == 500)
        #expect(status.fraction == 0.5)
        #expect(status.isOver == false)
        #expect(status.fxUnavailable == false)
    }

    @Test func overspendingIsReportedWithItsSize() throws {
        let context = try Self.makeContext()
        let groceries = Category(name: "כלכלת בית", kind: .expense)
        context.insert(groceries)
        context.insert(BudgetItem(plannedAmount: 1000, kind: .expense, category: groceries))
        let rows = [
            Transaction(amount: 700, kind: .expense, date: Self.date(2026, 9, 10), category: groceries),
            Transaction(amount: 450, kind: .expense, date: Self.date(2026, 9, 3), category: groceries)
        ]
        rows.forEach(context.insert)

        let status = try #require(CategoryBudgetStatus.make(
            category: groceries, containing: Self.date(2026, 9, 10),
            budgetItems: try context.fetch(FetchDescriptor<BudgetItem>()), transactions: rows,
            preferredCurrency: "ILS", fxSnapshot: nil
        ))
        #expect(status.isOver)
        #expect(status.overAmount == 150)
    }

    /// No plan for the category means no bar — never a bar against ₪0.
    @Test func noBudgetLineMeansNoStatus() throws {
        let context = try Self.makeContext()
        let groceries = Category(name: "כלכלת בית", kind: .expense)
        let dining = Category(name: "מסעדות", kind: .expense)
        context.insert(groceries); context.insert(dining)
        context.insert(BudgetItem(plannedAmount: 400, kind: .expense, category: dining))

        let status = CategoryBudgetStatus.make(
            category: groceries, containing: Self.date(2026, 9, 10),
            budgetItems: try context.fetch(FetchDescriptor<BudgetItem>()), transactions: [],
            preferredCurrency: "ILS", fxSnapshot: nil
        )
        #expect(status == nil)
    }

    /// Both sides land in the preferred currency; a currency with no rate is
    /// left out and flagged rather than added at face value.
    @Test func convertsCurrenciesAndFlagsMissingRates() throws {
        let context = try Self.makeContext()
        let groceries = Category(name: "כלכלת בית", kind: .expense)
        context.insert(groceries)
        context.insert(BudgetItem(plannedAmount: 1000, kind: .expense, category: groceries))
        let snapshot = FXRateSnapshot(base: "EUR", rates: ["ILS": 4.0, "USD": 1.0])
        context.insert(snapshot)
        let rows = [
            Transaction(amount: 100, kind: .expense, date: Self.date(2026, 9, 12), currencyCode: "USD", category: groceries),
            Transaction(amount: 50, kind: .expense, date: Self.date(2026, 9, 11), currencyCode: "GBP", category: groceries),
            Transaction(amount: 200, kind: .expense, date: Self.date(2026, 9, 10), category: groceries)
        ]
        rows.forEach(context.insert)

        let status = try #require(CategoryBudgetStatus.make(
            category: groceries, containing: Self.date(2026, 9, 10),
            budgetItems: try context.fetch(FetchDescriptor<BudgetItem>()), transactions: rows,
            preferredCurrency: "ILS", fxSnapshot: snapshot
        ))
        // $100 at 4 ILS per USD, plus ₪200; the GBP row has no rate.
        #expect(status.actual == 600)
        #expect(status.fxUnavailable)
    }
}
