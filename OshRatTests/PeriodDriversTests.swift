import Testing
import Foundation
import SwiftData
@testable import OshRat

/// "What's behind the change" — the analytics station after the comparison.
@MainActor
struct PeriodDriversTests {

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

    private static func month(_ year: Int, _ month: Int) -> DateInterval {
        calendar.dateInterval(of: .month, for: date(year, month, 15))!
    }

    /// August against July, both finished — compared whole.
    private static let finished = PeriodDrivers.Windows(
        current: month(2026, 8), previous: month(2026, 7), isPartial: false, elapsedDays: nil
    )

    // MARK: Windows

    @Test func aFinishedPeriodIsComparedWhole() {
        let windows = PeriodDrivers.windows(
            current: Self.month(2026, 8), previous: Self.month(2026, 7),
            now: Self.date(2026, 9, 27), calendar: Self.calendar
        )
        #expect(windows == Self.finished)
    }

    /// Sept 1–27 against Aug 1–27: the live month isn't set against a whole one.
    @Test func theLivePeriodIsComparedOverTheSameDays() {
        let windows = PeriodDrivers.windows(
            current: Self.month(2026, 9), previous: Self.month(2026, 8),
            now: Self.date(2026, 9, 27, 9), calendar: Self.calendar
        )
        #expect(windows.isPartial)
        #expect(windows.elapsedDays == 27)
        #expect(windows.current.end == Self.calendar.startOfDay(for: Self.date(2026, 9, 28)))
        #expect(windows.previous.end == Self.calendar.startOfDay(for: Self.date(2026, 8, 28)))
    }

    /// March 31 compares with all of February, not with a few days of March.
    @Test func thePreviousWindowIsClampedToItsOwnEnd() {
        let windows = PeriodDrivers.windows(
            current: Self.month(2026, 3), previous: Self.month(2026, 2),
            now: Self.date(2026, 3, 31), calendar: Self.calendar
        )
        #expect(windows.previous.end == Self.month(2026, 2).end)
    }

    // MARK: Categories

    @Test func categoriesAreRankedByTheSizeOfTheirSwing() throws {
        let context = try Self.makeContext()
        let dining = Category(name: "מסעדות", kind: .expense)
        let groceries = Category(name: "כלכלת בית", kind: .expense)
        let clothes = Category(name: "ביגוד", kind: .expense)
        [dining, groceries, clothes].forEach(context.insert)

        let rows = [
            Transaction(amount: 900, kind: .expense, date: Self.date(2026, 8, 10), category: dining),
            Transaction(amount: 300, kind: .expense, date: Self.date(2026, 7, 10), category: dining),
            Transaction(amount: 1000, kind: .expense, date: Self.date(2026, 8, 5), category: groceries),
            Transaction(amount: 1200, kind: .expense, date: Self.date(2026, 7, 5), category: groceries),
            Transaction(amount: 250, kind: .expense, date: Self.date(2026, 8, 20), category: clothes)
        ]
        rows.forEach(context.insert)

        let drivers = PeriodDrivers(transactions: rows, windows: Self.finished,
                                    preferredCurrency: "ILS", fxSnapshot: nil)
        #expect(drivers.expense.current == 2150)
        #expect(drivers.expense.previous == 1500)
        #expect(drivers.expense.categories.map(\.name) == ["מסעדות", "ביגוד", "כלכלת בית"])
        #expect(drivers.expense.categories.map(\.delta) == [600, 250, -200])
    }

    @Test func transfersAndBalanceEditsAreNotSpending() throws {
        let context = try Self.makeContext()
        let rows = [
            Transaction(amount: 100, kind: .expense, date: Self.date(2026, 8, 10)),
            Transaction(amount: 5000, kind: .expense, date: Self.date(2026, 8, 11), destinationAmount: 5000),
            Transaction(amount: 100, kind: .expense, date: Self.date(2026, 7, 10))
        ]
        rows.forEach(context.insert)
        let drivers = PeriodDrivers(transactions: rows, windows: Self.finished,
                                    preferredCurrency: "ILS", fxSnapshot: nil)
        #expect(drivers.expense.current == 100)
        #expect(drivers.expense.delta == 0)
    }

    // MARK: Habits

    @Test func countsAndAveragesAreKeptPerWindow() throws {
        let context = try Self.makeContext()
        let rows = (1...6).map { Transaction(amount: 100, kind: .expense, date: Self.date(2026, 8, $0)) }
            + (1...3).map { Transaction(amount: 200, kind: .expense, date: Self.date(2026, 7, $0)) }
        rows.forEach(context.insert)
        let drivers = PeriodDrivers(transactions: rows, windows: Self.finished,
                                    preferredCurrency: "ILS", fxSnapshot: nil)
        #expect(drivers.expense.currentCount == 6)
        #expect(drivers.expense.previousCount == 3)
        #expect(drivers.expense.currentAverage == 100)
        #expect(drivers.expense.previousAverage == 200)
    }

    @Test func noBaselineWithoutAPreviousPeriod() throws {
        let context = try Self.makeContext()
        let rows = [Transaction(amount: 250, kind: .expense, date: Self.date(2026, 8, 3))]
        rows.forEach(context.insert)
        let drivers = PeriodDrivers(transactions: rows, windows: Self.finished,
                                    preferredCurrency: "ILS", fxSnapshot: nil)
        #expect(drivers.expense.previousAverage == nil)
        #expect(drivers.hasBaseline == false)
    }

    // MARK: Notable expenses

    @Test func aOneOffPurchaseStandsOut() throws {
        let context = try Self.makeContext()
        let rows = (1...8).map { Transaction(amount: 60, kind: .expense, date: Self.date(2026, 8, $0)) }
            + [Transaction(amount: 4200, kind: .expense, date: Self.date(2026, 8, 12), title: "מחשב נייד")]
        rows.forEach(context.insert)
        let drivers = PeriodDrivers(transactions: rows, windows: Self.finished,
                                    preferredCurrency: "ILS", fxSnapshot: nil)
        #expect(drivers.notableExpenses.map(\.title) == ["מחשב נייד"])
    }

    /// Rent is big every month; that makes it a bill, not a standout.
    @Test func aRecurringBillIsNotAStandout() throws {
        let context = try Self.makeContext()
        let rent = Category(name: "שכר דירה", kind: .expense)
        context.insert(rent)
        let rows = (1...8).map { Transaction(amount: 60, kind: .expense, date: Self.date(2026, 8, $0)) }
            + [Transaction(amount: 5000, kind: .expense, date: Self.date(2026, 8, 1), category: rent),
               Transaction(amount: 4900, kind: .expense, date: Self.date(2026, 7, 1), category: rent)]
        rows.forEach(context.insert)
        let drivers = PeriodDrivers(transactions: rows, windows: Self.finished,
                                    preferredCurrency: "ILS", fxSnapshot: nil)
        #expect(drivers.notableExpenses.isEmpty)
    }

    /// Even spending has nothing to single out.
    @Test func evenSpendingHasNoStandouts() throws {
        let context = try Self.makeContext()
        let rows = (1...8).map { Transaction(amount: Decimal(50 + $0 * 5), kind: .expense, date: Self.date(2026, 8, $0)) }
        rows.forEach(context.insert)
        let drivers = PeriodDrivers(transactions: rows, windows: Self.finished,
                                    preferredCurrency: "ILS", fxSnapshot: nil)
        #expect(drivers.notableExpenses.isEmpty)
    }
}
