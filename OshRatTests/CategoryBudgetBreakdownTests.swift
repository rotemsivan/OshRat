import Testing
import Foundation
import SwiftData
@testable import OshRat

/// The analytics budget station: plan against reality, category by category.
@MainActor
struct CategoryBudgetBreakdownTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        return calendar
    }()

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
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func interval(_ unit: Calendar.Component, _ year: Int, _ month: Int = 6) -> DateInterval {
        calendar.dateInterval(of: unit, for: date(year, month, 15))!
    }

    private static func breakdown(
        _ context: ModelContext,
        _ rows: [Transaction],
        interval: DateInterval,
        now: Date? = nil
    ) throws -> CategoryBudgetBreakdown {
        CategoryBudgetBreakdown(
            budgetItems: try context.fetch(FetchDescriptor<BudgetItem>()),
            transactions: rows,
            interval: interval,
            preferredCurrency: "ILS",
            fxSnapshot: nil,
            calendar: calendar,
            now: now ?? date(2027, 1, 1)
        )
    }

    @Test func eachCategoryIsScoredAgainstItsOwnPlan() throws {
        let context = try Self.makeContext()
        let groceries = Category(name: "כלכלת בית", kind: .expense)
        let dining = Category(name: "מסעדות", kind: .expense)
        let gifts = Category(name: "מתנות", kind: .expense)
        [groceries, dining, gifts].forEach(context.insert)
        context.insert(BudgetItem(plannedAmount: 2000, kind: .expense, category: groceries))
        context.insert(BudgetItem(plannedAmount: 400, kind: .expense, category: dining))

        let rows = [
            Transaction(amount: 1500, kind: .expense, date: Self.date(2026, 6, 10), category: groceries),
            Transaction(amount: 650, kind: .expense, date: Self.date(2026, 6, 12), category: dining),
            Transaction(amount: 300, kind: .expense, date: Self.date(2026, 6, 20), category: gifts),
            Transaction(amount: 999, kind: .expense, date: Self.date(2026, 7, 1, 0), category: dining) // next month
        ]
        rows.forEach(context.insert)

        let budget = try Self.breakdown(context, rows, interval: Self.interval(.month, 2026))
        // The overrun sorts first.
        #expect(budget.rows.map(\.name) == ["מסעדות", "כלכלת בית"])
        #expect(budget.overruns.map(\.name) == ["מסעדות"])
        #expect(budget.overruns.first?.overAmount == 250)
        #expect(budget.unbudgeted.map(\.name) == ["מתנות"])
        #expect(budget.plannedExpense == 2400)
        // Unbudgeted spend still comes out of the total.
        #expect(budget.actualExpense == 2450)
        #expect(budget.isTotalOver)
    }

    /// A category can be over while the whole plan still has room.
    @Test func aCategoryOverrunIsReportedEvenWhenTheTotalIsFine() throws {
        let context = try Self.makeContext()
        let groceries = Category(name: "כלכלת בית", kind: .expense)
        let dining = Category(name: "מסעדות", kind: .expense)
        [groceries, dining].forEach(context.insert)
        context.insert(BudgetItem(plannedAmount: 2000, kind: .expense, category: groceries))
        context.insert(BudgetItem(plannedAmount: 400, kind: .expense, category: dining))
        let rows = [
            Transaction(amount: 500, kind: .expense, date: Self.date(2026, 6, 10), category: groceries),
            Transaction(amount: 650, kind: .expense, date: Self.date(2026, 6, 12), category: dining)
        ]
        rows.forEach(context.insert)

        let budget = try Self.breakdown(context, rows, interval: Self.interval(.month, 2026))
        #expect(budget.overruns.count == 1)
        #expect(budget.isTotalOver == false)
    }

    /// A yearly bill lands in the year's plan once, and in its own month only.
    @Test func aYearUsesEveryMonthsPlan() throws {
        let context = try Self.makeContext()
        let insurance = Category(name: "ביטוח", kind: .expense)
        let groceries = Category(name: "כלכלת בית", kind: .expense)
        [insurance, groceries].forEach(context.insert)
        context.insert(BudgetItem(plannedAmount: 1200, kind: .expense, recurrenceUnit: .year,
                                  scheduleMonth: 3, category: insurance))
        context.insert(BudgetItem(plannedAmount: 1000, kind: .expense, category: groceries))

        let year = try Self.breakdown(context, [], interval: Self.interval(.year, 2026))
        #expect(year.plannedExpense == 13_200)

        let june = try Self.breakdown(context, [], interval: Self.interval(.month, 2026, 6))
        #expect(june.rows.map(\.name) == ["כלכלת בית"])
    }

    @Test func incomeIsComparedWithItsPlan() throws {
        let context = try Self.makeContext()
        context.insert(BudgetItem(name: "משכורת", plannedAmount: 12_000, kind: .income))
        let rows = [Transaction(amount: 12_500, kind: .income, date: Self.date(2026, 6, 1))]
        rows.forEach(context.insert)

        let budget = try Self.breakdown(context, rows, interval: Self.interval(.month, 2026))
        #expect(budget.plannedIncome == 12_000)
        #expect(budget.actualIncome == 12_500)
        #expect(budget.overruns.isEmpty)
    }

    @Test func paceIsOnlyMarkedWhileThePeriodRuns() throws {
        let context = try Self.makeContext()
        let june = Self.interval(.month, 2026)

        let running = try Self.breakdown(context, [], interval: june, now: Self.date(2026, 6, 16, 0))
        let elapsed = try #require(running.elapsedFraction)
        #expect(abs(elapsed - 0.5) < 0.001)

        let over = try Self.breakdown(context, [], interval: june, now: Self.date(2026, 7, 2))
        #expect(over.elapsedFraction == nil)
        #expect(over.hasAnyBudget == false)
    }
}
