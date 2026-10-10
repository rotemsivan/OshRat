import Testing
import Foundation
import SwiftData
@testable import OshRat

/// The export's content: which rows go in, how they're signed and counted,
/// and that the summaries agree with the app's own rules.
@MainActor
struct TransactionExportTests {

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

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func month(_ year: Int, _ month: Int) -> DateInterval {
        calendar.dateInterval(of: .month, for: date(year, month, 15))!
    }

    private static func workbook(
        _ context: ModelContext,
        interval: DateInterval?,
        fx: FXRateSnapshot? = nil,
        now: Date? = nil
    ) throws -> ExportWorkbook {
        TransactionExport.workbook(
            transactions: try context.fetch(FetchDescriptor<Transaction>()),
            budgetItems: try context.fetch(FetchDescriptor<BudgetItem>()),
            accounts: try context.fetch(FetchDescriptor<Account>()),
            preferredCurrency: "ILS",
            fxSnapshot: fx,
            interval: interval,
            calendar: calendar,
            now: now ?? date(2026, 7, 15)
        )
    }

    /// The transactions table, and a reader for one column by its header.
    private static func ledger(_ workbook: ExportWorkbook) -> (table: ExportTable, column: (String) -> [ExportValue]) {
        let table = workbook.sheet(named: TransactionExport.SheetName.transactions)!.tables[0]
        return (table, { header in
            let index = table.columns.firstIndex { $0.header == header }!
            return table.rows.map { $0.cells[index].value }
        })
    }

    // MARK: - Transactions sheet

    @Test func onlyLiveRowsInsideTheWindowAreExportedOldestFirst() throws {
        let context = try Self.makeContext()
        let rows = [
            Transaction(amount: 10, kind: .expense, date: Self.date(2026, 6, 30, 23, 59), title: "late"),
            Transaction(amount: 20, kind: .expense, date: Self.date(2026, 6, 1, 0, 0), title: "first"),
            Transaction(amount: 30, kind: .expense, date: Self.date(2026, 7, 1, 0, 0), title: "next month"),
            Transaction(amount: 40, kind: .expense, date: Self.date(2026, 6, 10), title: "deleted"),
        ]
        rows[3].deletedAt = .now
        rows.forEach(context.insert)

        let (_, column) = Self.ledger(try Self.workbook(context, interval: Self.month(2026, 6)))
        #expect(column("כותרת") == [.text("first"), .text("late")])
    }

    @Test func amountsAreSignedTheWayMoneyMoved() throws {
        let context = try Self.makeContext()
        let wallet = Account(name: "ביט", type: .digitalWallet)
        let bank = Account(name: "עו״ש", type: .current)
        [wallet, bank].forEach(context.insert)
        context.insert(Transaction(amount: 100, kind: .income, date: Self.date(2026, 6, 1), title: "in"))
        context.insert(Transaction(amount: 40, kind: .expense, date: Self.date(2026, 6, 2), title: "out"))
        context.insert(Transaction(
            amount: 50, date: Self.date(2026, 6, 3), title: "move",
            account: bank, destinationAccount: wallet, destinationAmount: 50
        ))

        let (_, column) = Self.ledger(try Self.workbook(context, interval: Self.month(2026, 6)))
        #expect(column("סכום") == [.number(100), .number(-40), .number(50)])
        #expect(column("סוג") == [.text("הכנסה"), .text("הוצאה"), .text("העברה")])
        #expect(column("לחשבון")[2] == .text("ביט"))
    }

    @Test func aTimeIsOnlyExportedWhenItIsReal() throws {
        let context = try Self.makeContext()
        context.insert(Transaction(amount: 1, date: Self.date(2026, 6, 1, 9, 5), title: "old", hasTimeOfDay: false))
        context.insert(Transaction(amount: 1, date: Self.date(2026, 6, 2, 14, 32), title: "new", hasTimeOfDay: true))

        let (_, column) = Self.ledger(try Self.workbook(context, interval: Self.month(2026, 6)))
        #expect(column("שעה") == [.empty, .time(hour: 14, minute: 32)])
        #expect(column("תאריך") == [.date(year: 2026, month: 6, day: 1), .date(year: 2026, month: 6, day: 2)])
    }

    @Test func aRowWithNoRateIsLeftBlankAndCounted() throws {
        let context = try Self.makeContext()
        context.insert(Transaction(amount: 10, kind: .expense, date: Self.date(2026, 6, 1), currencyCode: "USD"))
        context.insert(Transaction(amount: 20, kind: .expense, date: Self.date(2026, 6, 2)))

        let workbook = try Self.workbook(context, interval: Self.month(2026, 6))
        let (_, column) = Self.ledger(workbook)
        #expect(column("סכום (₪)") == [.empty, .number(-20)])

        let overview = workbook.sheet(named: TransactionExport.SheetName.overview)!
        let details = overview.tables[0].rows.map { $0.cells[0].value }
        #expect(details.contains(.text("לא הומרו")))
    }

    @Test func aRateConvertsIntoThePreferredCurrency() throws {
        let context = try Self.makeContext()
        context.insert(Transaction(amount: 10, kind: .expense, date: Self.date(2026, 6, 1), currencyCode: "USD"))
        let fx = FXRateSnapshot(base: "EUR", rates: ["USD": 1.0, "ILS": 4.0])

        let (_, column) = Self.ledger(try Self.workbook(context, interval: Self.month(2026, 6), fx: fx))
        #expect(column("סכום (₪)") == [.number(-40)])
    }

    // MARK: - Summaries

    @Test func bookkeepingRowsAreListedButNeverCounted() throws {
        let context = try Self.makeContext()
        let bank = Account(name: "עו״ש")
        let wallet = Account(name: "ביט", type: .digitalWallet)
        [bank, wallet].forEach(context.insert)
        let luxury = Category(name: "מסעדות", kind: .expense, nature: .want)
        let need = Category(name: "סופר", kind: .expense, nature: .need)
        [luxury, need].forEach(context.insert)
        context.insert(Transaction(amount: 1000, kind: .income, date: Self.date(2026, 6, 1)))
        context.insert(Transaction(amount: 300, kind: .expense, date: Self.date(2026, 6, 2), category: need))
        context.insert(Transaction(amount: 100, kind: .expense, date: Self.date(2026, 6, 3), category: luxury))
        context.insert(Transaction(amount: 70, kind: .expense, date: Self.date(2026, 6, 4))) // uncategorised → need
        context.insert(Transaction(
            amount: 500, date: Self.date(2026, 6, 5), account: bank,
            destinationAccount: wallet, destinationAmount: 500
        ))
        context.insert(Transaction(
            amount: 999, kind: .income, date: Self.date(2026, 6, 6),
            title: Transaction.manualBalanceEditTitle, account: bank
        ))

        let workbook = try Self.workbook(context, interval: Self.month(2026, 6))
        #expect(Self.ledger(workbook).table.rows.count == 6)

        let june = workbook.sheet(named: TransactionExport.SheetName.monthly)!.tables[0].rows[0]
        let values = june.cells.map(\.value)
        // חודש, הכנסות, צרכים, מותרות, סה״כ, נטו, תנועות
        #expect(values[1] == .number(1000))
        #expect(values[2] == .number(370))
        #expect(values[3] == .number(100))
        #expect(values[4] == .number(470))
        #expect(values[5] == .number(530))
        #expect(values[6] == .number(4))
    }

    @Test func monthlyTotalsAgreeWithTheBudgetBreakdown() throws {
        let context = try Self.makeContext()
        let groceries = Category(name: "סופר", kind: .expense, nature: .need)
        context.insert(groceries)
        context.insert(BudgetItem(plannedAmount: 2000, kind: .expense, category: groceries))
        context.insert(BudgetItem(name: "משכורת", plannedAmount: 9000, kind: .income))
        let rows = [
            Transaction(amount: 1500, kind: .expense, date: Self.date(2026, 5, 10), category: groceries),
            Transaction(amount: 2500, kind: .expense, date: Self.date(2026, 6, 10), category: groceries),
            Transaction(amount: 9000, kind: .income, date: Self.date(2026, 6, 1)),
        ]
        rows.forEach(context.insert)

        let window = DateInterval(start: Self.month(2026, 5).start, end: Self.month(2026, 6).end)
        let workbook = try Self.workbook(context, interval: window)
        let monthly = workbook.sheet(named: TransactionExport.SheetName.monthly)!.tables[0]
        // Two months and a total row.
        #expect(monthly.rows.count == 3)
        #expect(monthly.rows[2].kind == .total)

        for (index, month) in [Self.month(2026, 5), Self.month(2026, 6)].enumerated() {
            let breakdown = CategoryBudgetBreakdown(
                budgetItems: try context.fetch(FetchDescriptor<BudgetItem>()),
                transactions: rows, interval: month, preferredCurrency: "ILS",
                fxSnapshot: nil, calendar: Self.calendar, now: Self.date(2026, 7, 15)
            )
            let values = monthly.rows[index].cells.map(\.value)
            #expect(values[4] == .number(breakdown.actualExpense))
            #expect(values[1] == .number(breakdown.actualIncome))
            #expect(values[8] == .number(breakdown.plannedExpense))
        }

        // June went over: the budget sheet's group row reads it as an overrun.
        let budget = workbook.sheet(named: TransactionExport.SheetName.budget)!.tables[0]
        let juneGroup = budget.rows.filter { $0.kind == .group }[1]
        #expect(juneGroup.cells[3].value == .number(-500))
        #expect(juneGroup.cells[4].role == .budgetPercent(.over))
    }

    @Test func thePivotAddsUpToTheCategoryTotals() throws {
        let context = try Self.makeContext()
        let groceries = Category(name: "סופר", kind: .expense, nature: .need)
        let dining = Category(name: "מסעדות", kind: .expense, nature: .want)
        [groceries, dining].forEach(context.insert)
        context.insert(Transaction(amount: 100, kind: .expense, date: Self.date(2026, 5, 3), category: groceries))
        context.insert(Transaction(amount: 200, kind: .expense, date: Self.date(2026, 6, 3), category: groceries))
        context.insert(Transaction(amount: 50, kind: .expense, date: Self.date(2026, 6, 4), category: dining))

        let window = DateInterval(start: Self.month(2026, 5).start, end: Self.month(2026, 6).end)
        let sheet = try Self.workbook(context, interval: window)
            .sheet(named: TransactionExport.SheetName.categories)!
        let pivot = sheet.tables[1]
        #expect(pivot.columns.count == 4)   // category, May, June, total
        #expect(pivot.rows[0].cells.map(\.value) == [.text("סופר"), .number(100), .number(200), .number(300)])
        #expect(pivot.rows[1].cells.map(\.value) == [.text("מסעדות"), .empty, .number(50), .number(50)])
        #expect(pivot.rows.last?.cells.map(\.value) == [.text("סה״כ"), .number(100), .number(250), .number(350)])
    }

    /// "This year" stops at the current month rather than listing empty
    /// future months.
    @Test func summariesStopAtTheCurrentMonth() throws {
        let context = try Self.makeContext()
        let year = Self.calendar.dateInterval(of: .year, for: Self.date(2026, 6, 1))!
        let workbook = try Self.workbook(context, interval: year, now: Self.date(2026, 3, 10))
        let monthly = workbook.sheet(named: TransactionExport.SheetName.monthly)!.tables[0]
        #expect(monthly.rows.filter { $0.kind == .body }.count == 3)
    }

    @Test func accountsAreSplitLikeTheAssetsCard() throws {
        let context = try Self.makeContext()
        context.insert(Account(name: "עו״ש", type: .current, balance: 1000))
        context.insert(Account(name: "פיקדון", type: .savings, balance: 5000))
        let gone = Account(name: "נמחק", balance: 99)
        gone.deletedAt = .now
        context.insert(gone)

        let sheet = try Self.workbook(context, interval: nil).sheet(named: TransactionExport.SheetName.accounts)!
        let rows = sheet.tables[0].rows
        #expect(rows.map { $0.cells[0].value } == [
            .text("נזיל"), .text("עו״ש"), .text("נכסים"), .text("פיקדון"), .text("סה״כ"),
        ])
        #expect(rows.last?.cells[4].value == .number(6000))
    }
}
