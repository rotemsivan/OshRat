import Testing
import Foundation
import SwiftData
@testable import OshRat

/// The data behind the analytics trend chart ("לאורך זמן").
@MainActor
struct MoneyFlowSeriesTests {

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

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private static func series(
        _ rows: [Transaction],
        _ granularity: MoneyFlowSeries.Granularity,
        now: Date? = nil
    ) -> MoneyFlowSeries {
        MoneyFlowSeries(
            transactions: rows, granularity: granularity,
            preferredCurrency: "ILS", fxSnapshot: nil,
            calendar: calendar, now: now ?? date(2026, 9, 15)
        )
    }

    /// Wants stack on their own; needs, neutral and uncategorised spending
    /// share the other part, so the two always add up to the whole expense.
    @Test func spendingSplitsIntoNeedsAndWants() throws {
        let context = try Self.makeContext()
        let groceries = Category(name: "כלכלת בית", kind: .expense, nature: .need)
        let dining = Category(name: "מסעדות", kind: .expense, nature: .want)
        let securities = Category(name: "קניית ני״ע", kind: .expense, nature: .neutral)
        [groceries, dining, securities].forEach(context.insert)
        let rows = [
            Transaction(amount: 5000, kind: .income, date: Self.date(2026, 9, 1)),
            Transaction(amount: 800, kind: .expense, date: Self.date(2026, 9, 3), category: groceries),
            Transaction(amount: 200, kind: .expense, date: Self.date(2026, 9, 4), category: dining),
            Transaction(amount: 300, kind: .expense, date: Self.date(2026, 9, 5), category: securities),
            Transaction(amount: 50, kind: .expense, date: Self.date(2026, 9, 6))
        ]
        rows.forEach(context.insert)

        let point = try #require(Self.series(rows, .month).points.last)
        #expect(point.income == 5000)
        #expect(point.wants == 200)
        #expect(point.needs == 1150)
        #expect(point.net == 3650)
    }

    /// Every month from the first entry to now is there, quiet ones as zero.
    @Test func monthsAreContiguousUpToNow() throws {
        let context = try Self.makeContext()
        let rows = [
            Transaction(amount: 100, kind: .expense, date: Self.date(2026, 6, 10)),
            Transaction(amount: 100, kind: .expense, date: Self.date(2026, 8, 10))
        ]
        rows.forEach(context.insert)

        let points = Self.series(rows, .month).points
        #expect(points.map(\.start) == [6, 7, 8, 9].map { Self.calendar.dateInterval(of: .month, for: Self.date(2026, $0, 1))!.start })
        #expect(points.map(\.expense) == [100, 0, 100, 0])
    }

    /// Years bucket the same rows by year.
    @Test func yearsSumTheirMonths() throws {
        let context = try Self.makeContext()
        let rows = [
            Transaction(amount: 1000, kind: .income, date: Self.date(2025, 3, 1)),
            Transaction(amount: 2000, kind: .income, date: Self.date(2025, 11, 1)),
            Transaction(amount: 500, kind: .income, date: Self.date(2026, 2, 1))
        ]
        rows.forEach(context.insert)

        let points = Self.series(rows, .year).points
        #expect(points.map(\.income) == [3000, 500])
    }

    /// A transfer or a manual balance correction is neither income nor spending.
    @Test func transfersAreLeftOut() throws {
        let context = try Self.makeContext()
        let from = Account(name: "עו״ש")
        let to = Account(name: "פיקדון")
        [from, to].forEach(context.insert)
        let transfer = Transaction(amount: 1000, kind: .expense, date: Self.date(2026, 9, 2),
                                   account: from, destinationAccount: to, destinationAmount: 1000)
        context.insert(transfer)

        #expect(Self.series([transfer], .month).points.isEmpty)
    }

    /// A tap lands anywhere inside a bar's month; it selects that month.
    @Test func aDateSelectsTheMonthContainingIt() throws {
        let context = try Self.makeContext()
        let row = Transaction(amount: 100, kind: .expense, date: Self.date(2026, 9, 10))
        context.insert(row)
        let series = Self.series([row], .month)

        let point = series.point(containing: Self.date(2026, 9, 28), calendar: Self.calendar)
        #expect(point?.expense == 100)
        #expect(series.point(containing: Self.date(2025, 1, 1), calendar: Self.calendar) == nil)
    }

    /// The period picked at the top may lie before the first entry: its
    /// figures are zeros for that month, not missing.
    @Test func aPeriodOutsideTheHistorySummarisesAsEmpty() throws {
        let context = try Self.makeContext()
        let row = Transaction(amount: 100, kind: .expense, date: Self.date(2026, 9, 10))
        context.insert(row)
        let series = Self.series([row], .month)

        let june = try #require(series.summary(for: Self.date(2025, 6, 20), calendar: Self.calendar))
        #expect(june.start == Self.calendar.dateInterval(of: .month, for: Self.date(2025, 6, 1))!.start)
        #expect(june.expense == 0 && june.income == 0)
        #expect(series.summary(for: Self.date(2026, 9, 1), calendar: Self.calendar)?.expense == 100)
    }
}
