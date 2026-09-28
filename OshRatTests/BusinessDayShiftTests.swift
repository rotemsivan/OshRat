import Testing
import Foundation
import SwiftData
@testable import OshRat

/// The Settings switch "הכנסות ביום עסקים" (`UserProfile.shiftsIncomeToBusinessDay`)
/// as `BudgetItem.occurrenceDate` applies it.
@MainActor
struct BusinessDayShiftTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// 1 August 2026 is a Saturday.
    @Test func incomeOnShabbatMovesToSundayOnlyWhileTheSettingIsOn() throws {
        let container = try ModelContainer(
            for: BudgetItem.self, Category.self, Transaction.self, Account.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let salary = BudgetItem(plannedAmount: 12_000, kind: .income, scheduleDay: 1)
        let rent = BudgetItem(plannedAmount: 4_000, kind: .expense, scheduleDay: 1)
        context.insert(salary); context.insert(rent)

        #expect(Self.calendar.component(.weekday, from: Self.day(2026, 8, 1)) == 7)

        let shifted = salary.occurrenceDate(inMonth: 8, year: 2026, calendar: Self.calendar)
        #expect(shifted == Self.day(2026, 8, 2))

        let unshifted = salary.occurrenceDate(
            inMonth: 8, year: 2026, calendar: Self.calendar, shiftIncomeToBusinessDay: false
        )
        #expect(unshifted == Self.day(2026, 8, 1))

        // Expenses keep their date either way.
        #expect(rent.occurrenceDate(inMonth: 8, year: 2026, calendar: Self.calendar) == Self.day(2026, 8, 1))
    }
}
